# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Stub Rails.cache so the gem's replay-tracking path can run without booting
# Rails. The fake mimics the subset of ActiveSupport::Cache::Store that the
# gem uses: write(key, value, expires_in:, unless_exist:).
class FakeCache
  def initialize
    @store = {}
  end

  def write(key, value, expires_in:, unless_exist: false)
    return false if unless_exist && @store.key?(key)

    @store[key] = { value: value, expires_in: expires_in }
    true
  end

  def read(key)
    entry = @store[key]
    entry && entry[:value]
  end

  def clear
    @store.clear
  end

  def keys
    @store.keys
  end

  def entry(key)
    @store[key]
  end
end

module Rails
  class << self
    attr_accessor :cache
  end
  self.cache = FakeCache.new
end

require "altcha-rails"
require "minitest/autorun"
