class CreateYnars < ActiveRecord::Migration[7.1]
  def change
    create_table :ynars do |t|
      t.string :content

      t.timestamps
    end
  end
end
