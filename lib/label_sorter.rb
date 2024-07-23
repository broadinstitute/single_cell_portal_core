# natural sorting of complex labels with strings and integers, like biosample_id entries
# adapted from https://rosettacode.org/wiki/Natural_sorting#Ruby
class LabelSorter
  include Comparable
  attr_reader :lowercase, :natural_types, :type_order

  def initialize(str)
    @str = str.to_s # safeguard against nil or non-string values
    @lowercase = @str.downcase
    @natural_types = @lowercase.scan(/\d+|\D+/).map { |s| s =~ /\d/ ? s.to_i : s }
    @type_order = @natural_types.map { |el| el.is_a?(Integer) ? :i : :s }.join
  end

  def <=> (other)
    if type_order.start_with?(other.type_order) || other.type_order.start_with?(type_order)
      natural_types <=> other.natural_types
    else
      lowercase <=> other.lowercase
    end
  end

  def to_s
    @str.dup
  end

  def self.natural_sort(values)
    sorted = values.map { |v| new(v) }.sort.map { |el| el.to_s }
    # move any blank/Unspecified entries to the end to allow use of first color for actual label
    if sorted.first.blank? || sorted.first == AnnotationVizService::MISSING_VALUE_LABEL
      sorted << sorted.shift
    end
    sorted
  end
end
