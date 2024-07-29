class AddAdminsToInternalGroup < Mongoid::Migration
  def self.up
    User.where(admin: true).map(&:add_to_admin_group)
  end

  def self.down
    User.where(admin: true).map(&:remove_from_admin_group)
  end
end
