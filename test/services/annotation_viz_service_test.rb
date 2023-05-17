require 'test_helper'

class AnnotationVizServiceTest < ActiveSupport::TestCase

  before(:all) do
    @user = FactoryBot.create(:user, test_array: @@users_to_clean)
    @basic_study = FactoryBot.create(:detached_study,
                                     name_prefix: 'Basic Viz',
                                     user: @user,
                                     test_array: @@studies_to_clean)
    @basic_study_cluster_file = FactoryBot.create(:cluster_file,
                                                  name: 'cluster_1.txt', study: @basic_study,
                                                  annotation_input: [
                                                    { name: 'Category', type: 'group', values: %w[bar bar baz] },
                                                    { name: 'Intensity', type: 'numeric', values: [1.1, 2.2, 3.3] }
                                                  ])
    @basic_study_cluster_file2 = FactoryBot.create(:cluster_file,
                                                   name: 'cluster_2.txt', study: @basic_study,
                                                   annotation_input: [
                                                     { name: 'Fizziness', type: 'group', values: %w[high low medium] },
                                                     { name: 'Buzziness', type: 'group', values: %w[large medium small] }
                                                   ])
    @basic_study_cluster_file3 = FactoryBot.create(:cluster_file,
                                                   name: 'cluster_3.txt', study: @basic_study,
                                                   annotation_input: [
                                                     { name: 'Blanks', type: 'group', values: ['foo', 'foo', ''] }
                                                   ])
    @basic_study_exp_file = FactoryBot.create(:study_file,
                                              name: 'dense.txt',
                                              file_type: 'Expression Matrix',
                                              study: @basic_study)

    @study_metadata_file = FactoryBot.create(:metadata_file,
                                             name: 'metadata.txt', study: @basic_study,
                                             annotation_input: [
                                               { name: 'species', type: 'group', values: %w[dog cat dog] },
                                               { name: 'disease', type: 'group', values: %w[none none measles] }
                                             ])
  end

  test 'gets the default annotation when no annotation name is specified' do
    annotation = AnnotationVizService.get_selected_annotation(@basic_study)
    assert_equal 'Category', annotation[:name]
    assert_equal %w[bar baz], annotation[:values]

    annotation = AnnotationVizService.get_selected_annotation(@basic_study, annot_scope: 'study')
    assert_equal 'species', annotation[:name]
    assert_equal %w[dog cat], annotation[:values]

    fizz_cluster = @basic_study.cluster_groups.find_by(name: 'cluster_2.txt')
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: fizz_cluster)
    assert_equal 'Fizziness', annotation[:name]
    assert_equal %w[high low medium], annotation[:values]

    @basic_study.update!(default_options: { cluster: 'cluster_1.txt', annotation: 'species--group--study' })
    annotation = AnnotationVizService.get_selected_annotation(@basic_study)
    assert_equal 'species', annotation[:name]
    assert_equal %w[dog cat], annotation[:values]
  end

  test 'can get annotations by name and scope' do
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, annot_name: 'disease', annot_type: 'group', annot_scope: 'study')
    assert_equal 'disease', annotation[:name]
    assert_equal %w[none measles], annotation[:values]

    cluster = @basic_study.cluster_groups.first
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: 'Intensity', annot_type: 'numeric', annot_scope: 'cluster')
    assert_equal 'Intensity', annotation[:name]
    assert_equal [1.1, 2.2, 3.3], annotation[:values]
  end

  test 'returns first study/cluster annotation if no matching annotation is found' do
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, annot_name: 'foobar', annot_scope: 'group', annot_type: 'study')
    assert_equal 'species', annotation[:name]
    cluster = @basic_study.cluster_groups.first
    annotation = AnnotationVizService.get_selected_annotation(@basic_study, cluster: cluster, annot_name: 'foobar', annot_type: 'group', annot_scope: 'cluster')
    assert_equal 'Category', annotation[:name]
  end

  test 'available annotations returns the available annotations' do
    annots = AnnotationVizService.available_annotations(@basic_study)
    assert_equal %w[species disease Category Intensity Fizziness Buzziness Blanks], (annots.map { |a| a[:name] })
    assert_equal [nil, nil, 'cluster_1.txt', 'cluster_1.txt', 'cluster_2.txt', 'cluster_2.txt', 'cluster_3.txt'],
                 (annots.map { |a| a[:cluster_name] })

    # if a cluster is specified, returns the study wide and annotations specific to that cluster
    cluster = @basic_study.cluster_groups.find_by(name: 'cluster_1.txt')
    annots = AnnotationVizService.available_annotations(@basic_study, cluster: cluster)
    assert_equal %w[species disease Category Intensity], (annots.map { |a| a[:name] })
  end

  test 'should sanitize blank values from annotation arrays' do
    blank_cluster = @basic_study.cluster_groups.find_by(name: 'cluster_3.txt')
    annotation = AnnotationVizService.get_selected_annotation(@basic_study,
                                                              cluster: blank_cluster, annot_name: 'Blanks',
                                                              annot_type: 'group', annot_scope: 'cluster')
    assert_equal 'Blanks', annotation[:name]
    assert_equal ['foo', AnnotationVizService::MISSING_VALUE_LABEL], annotation[:values]
  end

  test 'should return non-plottable annotations' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'No Valid Viz',
                              user: @user,
                              test_array: @@studies_to_clean)
    FactoryBot.create(:cluster_file, name: 'cluster_1.txt', study: study, annotation_input: [
      { name: 'cluster', type: 'group', values: %w[A A A] }
    ])
    FactoryBot.create(:metadata_file, name: 'metadata.txt', study: study, annotation_input: [
      { name: 'species', type: 'group', values: %w[dog dog dog] }
    ])
    annots = AnnotationVizService.available_annotations(study)
    assert_equal 2, annots.size
    cluster_annot = annots.detect { |a| a[:name] == 'cluster' }
    assert cluster_annot.present?
    assert_equal 'cluster_1.txt', cluster_annot[:cluster_name]
    assert_equal 'invalid', cluster_annot[:scope]
    species_annot = annots.detect { |a| a[:name] == 'species' }
    assert species_annot.present?
    assert_equal 'invalid', species_annot[:scope]
  end

  test 'should mark metadata ontology annotation validity' do
    study = FactoryBot.create(:detached_study,
                              name_prefix: 'metadata ontology',
                              user: @user,
                              test_array: @@studies_to_clean)

    FactoryBot.create(:metadata_file, name: 'metadata.txt', study: study, annotation_input: [
      { name: 'species', type: 'group', values: %w[id1 id1 id2] },
      { name: 'species__ontology_label', type: 'group', values: %w[dog dog cat] },
    ])
    annots = AnnotationVizService.available_annotations(study)
    assert_equal 2, annots.size
    species_annot = annots.detect { |a| a[:name] == 'species' }
    assert species_annot.present?
    assert_equal 'invalid', species_annot[:scope]

    species_label_annot = annots.detect { |a| a[:name] == 'species__ontology_label' }
    assert species_label_annot.present?
    assert_equal 'study', species_label_annot[:scope]

  end
end
