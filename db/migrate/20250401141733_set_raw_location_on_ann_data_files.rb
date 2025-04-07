class SetRawLocationOnAnnDataFiles < Mongoid::Migration
  def self.up
    files = StudyFile.where(
      file_type: 'AnnData', 'ann_data_file_info.reference_file' => false, parse_status: 'parsed'
    ).select(&:is_raw_counts_file?)
    files.each do |file|
      adata = file.ann_data_file_info
      exp_fragment = file.ann_data_file_info.find_fragment(data_type: :expression)
      next if adata.raw_location.present? || exp_fragment.blank?

      adata.raw_location = '.raw'
      exp_fragment[:raw_location] = '.raw'
      idx = file.ann_data_file_info.fragment_index_of(exp_fragment)
      file.ann_data_file_info.data_fragments[idx] = exp_fragment
      file.save
    end
  end

  def self.down
    files = StudyFile.where(
      file_type: 'AnnData', 'ann_data_file_info.reference_file' => false, parse_status: 'parsed'
    ).select(&:is_raw_counts_file?)
    files.each do |file|
      file.ann_data_file_info.raw_location = nil
      file.save
    end
  end
end
