require "test_helper"

class ActiveRecordCheckTest < Minitest::Test
  def setup
    @check = Rx::Check::ActiveRecordCheck.new
  end

  def test_it_fails_if_activerecord_is_not_defined
    result = @check.check
    assert !result.ok?
  end

  def test_it_succeeds_if_activerecord_is_defined
    @check.stub(:activerecord_defined?, true) do
      @check.class.const_set(:ActiveRecord, Module.new)
      Rx::Check::ActiveRecordCheck::ActiveRecord.const_set(:Base, Class.new do
        def self.connection_pool
          Minitest::Mock.new.expect(:with_connection, Minitest::Mock.new.expect(:present?, true))
        end
      end)
      assert @check.check.ok?
    end
  ensure
    Rx::Check::ActiveRecordCheck.send(:remove_const, :ActiveRecord)
  end
end
