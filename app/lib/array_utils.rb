module ArrayUtils
  # create a "typed array" object for use in Plotly rendering
  # see https://github.com/plotly/plotly.js/pull/5230 for more information
  # see https://ruby-doc.org/core-3.0.1/Array.html#method-i-pack and
  # https://numpy.org/doc/stable/reference/arrays.dtypes.html for information about data types
  def self.typed_array(array)
    return array if array.blank? || array.first.is_a?(String)

    if array.first.is_a?(Integer)
      dtype = 'i4' # 32-bit signed integer from numpy#dtypes
      formatter = 'l*' # 32-bit signed integer, native endian from Array#pack
    else
      dtype = 'f8' # 64-bit floating-point number from numpy#dtypes
      formatter = 'd*' # double-precision, native format float from Array#pack
    end

    {
      dtype:,
      bdata: Base64.strict_encode64(array.pack(formatter))
    }
  end
end
