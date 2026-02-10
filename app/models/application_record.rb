class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  connects_to database: { writing: :primary, replica_1: :replica_1, replica_2: :replica_2 }
end
