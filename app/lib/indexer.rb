# common methods for creating indexes of data
module Indexer

  # convert an array of values to hash of indexes
  # e.g. ['a', 'b', 'c'] => { a: 0, b: 1, c: 2 }
  # can only be used with unique arrays like cell names
  def array_to_hashmap(array)
    array.index_with.with_index { |_, index| index }
  end
end
