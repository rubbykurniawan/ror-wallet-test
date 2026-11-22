class WalletAccessPolicy
  def initialize(user)
    @user = user
  end

  def read?(wallet)
    own_user_wallet?(wallet)
  end

  def debit?(wallet)
    own_user_wallet?(wallet)
  end

  def deposit?(wallet)
    own_user_wallet?(wallet)
  end

  def transfer_target?(_wallet)
    true
  end

  private

  attr_reader :user

  def own_user_wallet?(wallet)
    wallet.owner_type == user.class.base_class.name && wallet.owner_id == user.id
  end
end
