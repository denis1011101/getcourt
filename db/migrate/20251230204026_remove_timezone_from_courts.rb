class RemoveTimezoneFromCourts < ActiveRecord::Migration[8.0]
  def change
    if index_exists?(:courts, :timezone)
      remove_index :courts, :timezone
    end

    # удаляем колонку timezone из courts
    remove_column :courts, :timezone, :string, if_exists: true
  end
end
