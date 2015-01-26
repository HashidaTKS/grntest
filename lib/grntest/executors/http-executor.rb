# -*- coding: utf-8 -*-
#
# Copyright (C) 2012-2015  Kouhei Sutou <kou@clear-code.com>
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

require "open-uri"

require "grntest/executors/base-executor"

module Grntest
  module Executors
    class HTTPExecutor < BaseExecutor
      def initialize(host, port, context=nil)
        super(context)
        @host = host
        @port = port
        @read_timeout = 3
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
        rescue SystemCallError
          n_retried += 1
          sleep(0.1)
          retry if n_retried < 10
          raise
        end
      end

      def shutdown
        send_command(command("shutdown"))
      end

      def create_sub_executor(context)
        self.class.new(@host, @port, context)
      end

      private
      def command(command_line)
        Groonga::Command::Parser.parse(command_line)
      end

      MAX_URI_SIZE = 4096
      def send_load_command(command)
        lines = command.original_source.lines
        if lines.size == 1 and command.to_uri_format.size <= MAX_URI_SIZE
          return send_normal_command(command)
        end

        values = command.arguments.delete(:values)
        if lines.size >= 2 and lines[1].start_with?("[")
          command.arguments.delete(:columns)
          body = lines[1..-1].join
        else
          body = values
        end

        request = Net::HTTP::Post.new(command.to_uri_format)
        request.content_type = "application/json; charset=UTF-8"
        request.body = body
        response = Net::HTTP.start(@host, @port) do |http|
          http.read_timeout = @read_timeout
          http.request(request)
        end
        normalize_response_data(command, response.body)
      end

      def send_normal_command(command)
        url = "http://#{@host}:#{@port}#{command.to_uri_format}"
        begin
          open(url, :read_timeout => @read_timeout) do |response|
            normalize_response_data(command, response.read)
          end
        rescue OpenURI::HTTPError
          $!.io.read
        end
      end

      def normalize_response_data(command, raw_response_data)
        if raw_response_data.empty? or command.output_type == :none
          raw_response_data
        else
          "#{raw_response_data}\n"
        end
      end
    end
  end
end
