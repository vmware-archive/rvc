require 'test_helper'

class MetricTest < Test::Unit::TestCase
  def test_decimal_str
    [
      [0.2,       '', '0.20'],
      [2,          '',  '2.00'],
      [2,          'B', '2.00 B'],
      [2 * 10**3,  'B', '2.00 kB'],
      [2 * 10**6,  'B', '2.00 MB'],
      [2 * 10**9,  'B', '2.00 GB'],
      [2 * 10**12, 'B', '2.00 TB'],
      [2 * 10**15, 'B', '2.00 PB'],
      [2 * 10**18, 'B', '2000.00 PB'],
    ].each do |v, u, s|
      assert_equal MetricNumber.new(v, u).to_s, s, "test #{[v,u,s].inspect}"
    end
  end

  def test_binary_str
    [
      [0.2,       '', '0.20'],
      [2,         '', '2.00'],
      [2,         'B', '2.00 B'],
      [2 * 2**10, 'B', '2.00 KiB'],
      [2 * 2**20, 'B', '2.00 MiB'],
      [2 * 2**30, 'B', '2.00 GiB'],
      [2 * 2**40, 'B', '2.00 TiB'],
      [2 * 2**50, 'B', '2.00 PiB'],
      [2 * 2**60, 'B', '2048.00 PiB'],
    ].each do |v, u, s|
      assert_equal MetricNumber.new(v, u, true).to_s, s, "test #{[v,u,s].inspect}"
    end
  end

  def assert_metrics_equal a, b, msg=nil
    assert_equal a, b, "a != b in #{msg}"
    assert_equal a.unit, b.unit, "a.unit != b.unit in #{msg}"
    assert_equal a.binary, b.binary, "a.binary != b.binary in #{msg}"
  end

  def test_decimal_parse
    [
      [2,          '',  '2'],
      [2,          'B', '2B'],
      [2,          'B', '2 B'],
      [2 * 10**3,  'B', '2 kB'],
      [2 * 10**3,  'B', '2 KB'],
      [2 * 10**6,  'B', '2 MB'],
      [2 * 10**9,  'B', '2 GB'],
      [2 * 10**12, 'B', '2 TB'],
      [2 * 10**15, 'B', '2 PB'],
      [2 * 10**18, 'B', '2000 PB'],
      [3140000,    'B', '3140 kB'],
      [3140000,    'B', '3.14 MB'],
      [3140000,    'B', '3,140,000.00 B'],
      [500,        'B', '0.5 KB'],
    ].each do |v, u, s|
      assert_metrics_equal MetricNumber.new(v, u), MetricNumber.parse(s), "test #{[v,u,s].inspect}"
    end
  end

  def test_binary_parse
    [
      [2 * 2**10,  'B', '2 KiB'],
      [2 * 2**20,  'B', '2 MiB'],
      [2 * 2**30,  'B', '2 GiB'],
      [2 * 2**40,  'B', '2 TiB'],
      [2 * 2**50,  'B', '2 PiB'],
      [2 * 2**60,  'B', '2048 PiB'],
      [3215360,    'B', '3140 KiB'],
      [3670016,    'B', '3.5 MIB'],
      [512,        'B', '0.5 KiB'],
    ].each do |v, u, s|
      assert_metrics_equal MetricNumber.new(v, u, true), MetricNumber.parse(s), "test #{[v,u,s].inspect}"
    end
  end
end
