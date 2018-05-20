class EnableUuid < ActiveRecord::Migration[5.2]
  def up
    enable_extension 'uuid-ossp'
    enable_extension 'pgcrypto'
  end

  def down
    disable_extension 'uuid-ossp'
    disable_extension 'pgcrypto'
  end
end
