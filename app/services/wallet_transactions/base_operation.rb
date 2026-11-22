require "digest"

module WalletTransactions
  class BaseOperation
    MAX_AMOUNT = BigDecimal("999999999999999999.99")

    def self.call(**arguments)
      new(**arguments).call
    end

    def initialize(actor:, amount:, idempotency_key:, source_wallet: nil, target_wallet: nil)
      @actor = actor
      @amount = normalize_amount(amount)
      @idempotency_key = normalize_key(idempotency_key)
      @source_wallet = source_wallet
      @target_wallet = target_wallet
    end

    private

    attr_reader :actor, :amount, :idempotency_key, :source_wallet, :target_wallet

    def execute(transaction_type:, source:, target:)
      validate_actor!
      validate_wallets!(transaction_type, source, target)
      fingerprint = request_fingerprint(transaction_type, source, target)

      begin
        Wallet.transaction do
          locked_wallets = lock_wallets(source, target)
          source = locked_wallets[source.id] if source
          target = locked_wallets[target.id] if target
          validate_wallets!(transaction_type, source, target)

          existing = existing_transaction
          return existing if existing && matching_request!(existing, fingerprint)

          if source && source.balance < amount
            raise InsufficientFunds, "source wallet has insufficient funds"
          end

          transaction = WalletTransaction.create!(
            actor: actor,
            transaction_type: transaction_type,
            source_wallet: source,
            target_wallet: target,
            amount: amount,
            idempotency_key: idempotency_key,
            request_fingerprint: fingerprint
          )

          entries = case transaction_type
          when "deposit" then [ [ target, amount ] ]
          when "withdraw" then [ [ source, -amount ] ]
          when "transfer" then [ [ source, -amount ], [ target, amount ] ]
          end
          entries.each do |wallet, signed_amount|
            transaction.ledger_entries.create!(wallet: wallet, amount: signed_amount)
          end

          transaction
        end
      rescue ActiveRecord::RecordNotUnique
        existing = existing_transaction
        raise unless existing

        matching_request!(existing, fingerprint)
        existing
      end
    end

    def normalize_amount(value)
      amount = BigDecimal(value.to_s)
      unless amount.finite? && amount.positive? && amount == amount.round(2) && amount <= MAX_AMOUNT
        raise InvalidRequest, "amount must be positive, have at most two decimal places, and fit decimal(20,2)"
      end

      amount
    rescue ArgumentError, TypeError
      raise InvalidRequest, "amount must be a valid decimal number"
    end

    def normalize_key(value)
      key = value.to_s
      raise InvalidRequest, "idempotency key must be present and at most 255 characters" if key.blank? || key.length > 255

      key
    end

    def validate_actor!
      raise Forbidden, "actor must be a persisted user" unless actor.is_a?(User) && actor.persisted?
    end

    def validate_wallets!(transaction_type, source, target)
      expected = {
        "deposit" => [ nil, true ],
        "withdraw" => [ true, nil ],
        "transfer" => [ true, true ]
      }.fetch(transaction_type)
      raise InvalidRequest, "source or target wallet is missing" unless (!!source == !!expected[0]) && (!!target == !!expected[1])
      raise InvalidRequest, "wallets must be persisted" if [ source, target ].compact.any? { |wallet| !wallet.is_a?(Wallet) || !wallet.persisted? }
      raise InvalidRequest, "transfer wallets must differ" if source && target && source.id == target.id
      raise InvalidRequest, "wallet currency mismatch" if source && target && source.currency != target.currency

      raise Forbidden, "deposit target must be actor's own user wallet" if transaction_type == "deposit" && !owned_by_actor?(target)
      raise Forbidden, "source must be actor's own user wallet" if source && !owned_by_actor?(source)
    end

    def owned_by_actor?(wallet)
      wallet.owner_type == actor.class.base_class.name && wallet.owner_id == actor.id
    end

    def request_fingerprint(transaction_type, source, target)
      canonical = [ transaction_type, source&.id, target&.id, amount.to_s("F") ].join(":")
      Digest::SHA256.hexdigest(canonical)
    end

    def existing_transaction
      WalletTransaction.find_by(actor: actor, idempotency_key: idempotency_key)
    end

    def matching_request!(existing, fingerprint)
      return existing if ActiveSupport::SecurityUtils.secure_compare(existing.request_fingerprint, fingerprint)

      raise IdempotencyConflict, "idempotency key was already used for a different request"
    end

    def lock_wallets(source, target)
      ids = [ source, target ].compact.map(&:id).uniq.sort
      locked = Wallet.where(id: ids).order(:id).lock.to_a.index_by(&:id)
      raise InvalidRequest, "wallet no longer exists" unless locked.size == ids.size

      locked
    end
  end
end
