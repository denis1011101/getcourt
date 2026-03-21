class CreateTranslationCaches < ActiveRecord::Migration[8.1]
  def change
    create_table :translation_caches do |t|
      t.string :text_hash, null: false
      t.text   :text_en,   null: false
      t.timestamps
    end
    add_index :translation_caches, :text_hash, unique: true
  end
end
