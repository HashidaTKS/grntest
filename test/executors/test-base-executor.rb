# Copyright (C) 2013-2014  Kouhei Sutou <kou@clear-code.com>
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

require "grntest/executors/base-executor"

class TestBaseExecutor < Test::Unit::TestCase
  def setup
    @context = Grntest::ExecutionContext.new
    @executor = Grntest::Executors::BaseExecutor.new(@context)
  end

  class TestErrorLogLevel < self
    data("emergency" => :emergency,
         "alert"     => :alert,
         "critical"  => :critical,
         "error"     => :error,
         "warning"   => :warning)
    def test_important_log_level(level)
      assert do
        @executor.send(:important_log_level?, level)
      end
    end

    data("notice"  => :notice,
         "info"    => :information,
         "debug"   => :debug,
         "dump"    => :dump)
    def test_not_important_log_level(level)
      assert do
        not @executor.send(:important_log_level?, level)
      end
    end
  end
end
