module WalletOwner
  module Registry
    @owner_types = []

    def self.register(owner_class)
      @owner_types |= [owner_class.name]
    end

    def self.owner_types
      @owner_types.dup
    end

    def self.registered?(owner_type)
      @owner_types.include?(owner_type)
    end
  end

  extend ActiveSupport::Concern

  included do
    WalletOwner::Registry.register(self)
    has_many :wallets, as: :owner, dependent: :restrict_with_exception
  end
end
