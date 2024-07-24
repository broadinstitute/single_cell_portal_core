require 'test_helper'

class LabelSorterTest < ActiveSupport::TestCase
  before(:all) do
    # these labels are already in the correct order
    @labels = %w(CS13 CS14 CS15 CS22_2_hypo CS22_hypo GW7_Lane1 GW7_Lane2 GW8_1 GW8_2 GW10 GW12_01 GW12_02 GW15_A GW15_M
                 GW15_P GW16_hypo GW18_A GW18_hypo GW18_Lane1 GW18_Lane2 GW18_Lane3 GW18_M GW18_P GW19_hypo GW20_34_hypo
                 GW20_A GW20_M GW20_P GW22T_hypo1 GW25_3V_hypo)
  end

  test 'should naturally sort list of complex labels' do
    unsorted = @labels.shuffle
    sorted = LabelSorter.natural_sort(unsorted)
    assert_equal @labels, sorted
  end

  test 'should compare labels' do
    first = LabelSorter.new('Biosample_3_A_4')
    middle = LabelSorter.new('Biosample_3_A_10')
    last = LabelSorter.new('Biosample_12_B_1')
    assert_equal 0, first <=> first
    assert_equal 0, middle <=> middle
    assert_equal 0, last <=> last
    assert_equal -1, first <=> middle
    assert_equal -1, first <=> last
    assert_equal -1, middle <=> last
    assert_equal 1, middle <=> first
    assert_equal 1, last <=> first
    assert_equal 1, last <=> middle
  end

  test 'should move blank or unspecified to the end' do
    random = @labels.take(10).shuffle
    blank_label = [''] + random
    sorted = LabelSorter.natural_sort(blank_label)
    assert sorted.last.blank?
    unspecified = [AnnotationVizService::MISSING_VALUE_LABEL] + random
    sorted = LabelSorter.natural_sort(unspecified)
    assert_equal AnnotationVizService::MISSING_VALUE_LABEL, sorted.last
  end
end
