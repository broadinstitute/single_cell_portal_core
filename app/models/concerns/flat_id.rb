# module to flatten BSON::ObjectId entries into strings when calling :attributes
module FlatId
  def flat_attributes
    attributes.map do |name, value|
      if name =~ /_id/
        { name.to_sym => value.to_s }
      else
        { name.to_sym => value }
      end
    end.reduce({}, :merge!)
  end
end
