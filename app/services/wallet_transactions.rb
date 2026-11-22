module WalletTransactions
  class Error < StandardError; end
  class InvalidRequest < Error; end
  class Forbidden < Error; end
  class InsufficientFunds < Error; end
  class IdempotencyConflict < Error; end
end
