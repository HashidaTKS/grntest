# -*- coding: utf-8 -*-
#
# Copyright (C) 2012-2013  Kouhei Sutou <kou@clear-code.com>
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

require "grntest/reporters/mark-reporter"
require "grntest/reporters/stream-reporter"
require "grntest/reporters/inplace-reporter"

module Grntest
  module Reporters
    class << self
      def create_repoter(tester)
        case tester.reporter
        when :mark
          MarkReporter.new(tester)
        when :stream
          StreamReporter.new(tester)
        when :inplace
          InplaceReporter.new(tester)
        end
      end
    end
  end
end
