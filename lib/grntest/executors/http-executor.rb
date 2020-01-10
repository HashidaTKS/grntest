# Copyright (C) 2012-2019  Sutou Kouhei <kou@clear-code.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require "arrow"
require "net/http"
require "open-uri"

require "grntest/executors/base-executor"

module Grntest
  module Executors
    class HTTPExecutor < BaseExecutor
      def initialize(host, port, context)
        super(context)
        @host = host
        @port = port
      end

      def send_command(command)
        if command.name == "load"
          send_load_command(command)
        else
          send_normal_command(command)
        end
      end

      def ensure_groonga_ready
        n_retried = 0
        begin
          send_command(command("status"))
        rescue Error
          n_retried += 1
          sleep(0.1)
          retry if n_retried < 100
          raise
        end
      end

      def create_sub_executor(context)
        self.class.new(@host, @port, context)
      end

      private
      MAX_URI_SIZE = 4096
      def send_load_command(command)
        lines = command.original_source.lines
        if lines.size == 1 and command.to_uri_format.size <= MAX_URI_SIZE
          return send_normal_command(command)
        end

        columns = nil
        values = command.arguments.delete(:values)
        if lines.size >= 2 and lines[1].start_with?("[")
          if /\s--columns\s/ =~ lines.first
            columns = command.columns
          else
            command.arguments.delete(:columns)
          end
          body = lines[1..-1].join
        else
          body = values
        end

        case @context.input_type
        when "apache-arrow"
          command[:input_type] = "apache-arrow"
          content_type = "application/x-apache-arrow-streaming"
          buffer = build_apache_arrow_data(columns, JSON.parse(body))
          if buffer.nil?
            body = ""
          else
            body = buffer.data.to_s
          end
        else
          content_type = "application/json; charset=UTF-8"
          body = body
        end
        request = Net::HTTP::Post.new(command.to_uri_format)
        request.content_type = content_type
        request.body = body
        response = Net::HTTP.start(@host, @port) do |http|
          http.read_timeout = read_timeout
          http.request(request)
        end
        normalize_response_data(command, response.body)
      end

      def build_apache_arrow_data(columns, values)
        table = {}
        if values.first.is_a?(Array)
          if columns
            records = values
          else
            columns = values.first
            records = values[1..-1]
          end
          records.each_with_index do |record, i|
            columns.zip(record).each do |name, value|
              table[name] ||= []
              table[name][i] = value
            end
          end
        else
          values.each_with_index do |record, i|
            record.each do |name, value|
              table[name] ||= []
              table[name][i] = value
            end
          end
          table.each_key do |key|
            if values.size > table[key].size
              table[key][values.size - 1] = nil
            end
          end
        end
        return nil if table.empty?
        arrow_table = build_apache_arrow_table(table)
        buffer = Arrow::ResizableBuffer.new(1024)
        arrow_table.save(buffer, format: :stream)
        buffer
      end

      def build_apache_arrow_table(table)
        arrow_fields = []
        arrow_arrays = []
        table.each do |name, array|
          sample = array.find {|element| not element.nil?}
          case sample
          when Array
            data_type = nil
            array.each do |sub_array|
              data_type ||= detect_arrow_data_type(sub_array) if sub_array
            end
            data_type ||= :string
            arrow_array = build_apache_arrow_array(data_type, array)
          when Hash
            arrow_array = build_apache_arrow_array(arrow_weight_vector_data_type,
                                                   array)
          else
            data_type = detect_arrow_data_type(array) || :string
            if data_type == :string
              array = array.collect do |element|
                element&.to_s
              end
            end
            data_type = Arrow::DataType.resolve(data_type)
            arrow_array = data_type.build_array(array)
          end
          arrow_fields << Arrow::Field.new(name,
                                           arrow_array.value_data_type)
          arrow_arrays << arrow_array
        end
        arrow_schema = Arrow::Schema.new(arrow_fields)
        Arrow::Table.new(arrow_schema, arrow_arrays)
      end

      def convert_array_for_apache_arrow(array)
        array.collect do |element|
          case element
          when Array
            convert_array_for_apache_arrow(element)
          when Hash
            element.collect do |value, weight|
              {
                "value" => value,
                "weight" => weight,
              }
            end
          else
            element
          end
        end
      end

      def build_apache_arrow_array(data_type, array)
        arrow_list_field = Arrow::Field.new("item", data_type)
        arrow_list_data_type = Arrow::ListDataType.new(arrow_list_field)
        array = convert_array_for_apache_arrow(array)
        arrow_array = Arrow::ListArrayBuilder.build(arrow_list_data_type,
                                                    array)
      end

      def arrow_weight_vector_data_type
        Arrow::StructDataType.new("value" => :string,
                                  "weight" => :int32)
      end

      def detect_arrow_data_type(array)
        type = nil
        array.each do |element|
          case element
          when nil
          when true, false
            type ||= :boolean
          when Integer
            if element >= (2 ** 63)
              type = nil if type == :int64
              type ||= :uint64
            else
              type ||= :int64
            end
          when Float
            type = nil if type == :int64
            type ||= :double
          when Hash
            arrow_list_field =
              Arrow::Field.new("item", arrow_weight_vector_data_type)
            arrow_list_data_type = Arrow::ListDataType.new(arrow_list_field)
            return arrow_list_data_type
          else
            return :string
          end
        end
        type
      end

      def send_normal_command(command)
        path_with_query = command.to_uri_format
        if @context.use_http_post?
          path, query = path_with_query.split("?", 2)
          request = Net::HTTP::Post.new(path)
          request.content_type = "application/x-www-form-urlencoded"
          request.body = query
        else
          request = Net::HTTP::Get.new(path_with_query)
        end
        url = "http://#{@host}:#{@port}#{path_with_query}"
        begin
          response = Net::HTTP.start(@host, @port) do |http|
            http.read_timeout = read_timeout
            http.request(request)
          end
          normalize_response_data(command, response.body)
        rescue SystemCallError
          message = "failed to read response from Groonga: <#{url}>: #{$!}"
          raise Error.new(message)
        rescue Net::HTTPBadResponse
          message = "bad response from Groonga: <#{url}>: "
          message << "#{$!.class}: #{$!.message}"
          raise Error.new(message)
        rescue Net::HTTPHeaderSyntaxError
          message = "bad HTTP header syntax in Groonga response: <#{url}>: "
          message << "#{$!.class}: #{$!.message}"
          raise Error.new(message)
        end
      end

      def normalize_response_data(command, raw_response_data)
        if raw_response_data.empty? or command.output_type == :none
          raw_response_data
        else
          "#{raw_response_data}\n"
        end
      end

      def read_timeout
        if @context.timeout.zero?
          nil
        else
          @context.timeout
        end
      end
    end
  end
end
