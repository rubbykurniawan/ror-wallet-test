class AddWalletIntegrityTriggers < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION prevent_ledger_entry_mutation() RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'ledger entries are immutable'
          USING ERRCODE = '55000';
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER ledger_entries_are_immutable
      BEFORE UPDATE OR DELETE ON ledger_entries
      FOR EACH ROW EXECUTE FUNCTION prevent_ledger_entry_mutation();

      CREATE FUNCTION prevent_wallet_transaction_financial_mutation() RETURNS trigger AS $$
      BEGIN
        IF EXISTS (SELECT 1 FROM ledger_entries WHERE wallet_transaction_id = OLD.id) THEN
          RAISE EXCEPTION 'wallet transactions with ledger entries are immutable'
            USING ERRCODE = '55000';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER wallet_transactions_are_immutable
      BEFORE UPDATE OF transaction_type, actor_id, source_wallet_id, target_wallet_id,
        amount, idempotency_key, request_fingerprint ON wallet_transactions
      FOR EACH ROW EXECUTE FUNCTION prevent_wallet_transaction_financial_mutation();

      CREATE FUNCTION validate_wallet_transaction_entries() RETURNS trigger AS $$
      DECLARE
        transaction_id bigint;
        transaction_record wallet_transactions%ROWTYPE;
        entry_count bigint;
      BEGIN
        IF TG_TABLE_NAME = 'wallet_transactions' THEN
          transaction_id := NEW.id;
        ELSE
          transaction_id := NEW.wallet_transaction_id;
        END IF;

        SELECT * INTO transaction_record
        FROM wallet_transactions
        WHERE id = transaction_id;

        IF NOT FOUND THEN
          RETURN NULL;
        END IF;

        SELECT COUNT(*) INTO entry_count
        FROM ledger_entries
        WHERE wallet_transaction_id = transaction_id;

        IF transaction_record.transaction_type = 'deposit' THEN
          IF entry_count <> 1 OR NOT EXISTS (
            SELECT 1 FROM ledger_entries
            WHERE wallet_transaction_id = transaction_id
              AND wallet_id = transaction_record.target_wallet_id
              AND amount = transaction_record.amount
          ) THEN
            RAISE EXCEPTION 'deposit transaction must have one matching credit entry'
              USING ERRCODE = '23514';
          END IF;
        ELSIF transaction_record.transaction_type = 'withdraw' THEN
          IF entry_count <> 1 OR NOT EXISTS (
            SELECT 1 FROM ledger_entries
            WHERE wallet_transaction_id = transaction_id
              AND wallet_id = transaction_record.source_wallet_id
              AND amount = -transaction_record.amount
          ) THEN
            RAISE EXCEPTION 'withdraw transaction must have one matching debit entry'
              USING ERRCODE = '23514';
          END IF;
        ELSIF transaction_record.transaction_type = 'transfer' THEN
          IF entry_count <> 2 OR NOT EXISTS (
            SELECT 1 FROM ledger_entries
            WHERE wallet_transaction_id = transaction_id
              AND wallet_id = transaction_record.source_wallet_id
              AND amount = -transaction_record.amount
          ) OR NOT EXISTS (
            SELECT 1 FROM ledger_entries
            WHERE wallet_transaction_id = transaction_id
              AND wallet_id = transaction_record.target_wallet_id
              AND amount = transaction_record.amount
          ) THEN
            RAISE EXCEPTION 'transfer transaction must have matching debit and credit entries'
              USING ERRCODE = '23514';
          END IF;
        END IF;

        RETURN NULL;
      END;
      $$ LANGUAGE plpgsql;

      CREATE CONSTRAINT TRIGGER wallet_transactions_have_valid_entries
      AFTER INSERT ON wallet_transactions
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION validate_wallet_transaction_entries();

      CREATE CONSTRAINT TRIGGER ledger_entries_match_transaction
      AFTER INSERT ON ledger_entries
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW EXECUTE FUNCTION validate_wallet_transaction_entries();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS ledger_entries_match_transaction ON ledger_entries;
      DROP TRIGGER IF EXISTS wallet_transactions_have_valid_entries ON wallet_transactions;
      DROP TRIGGER IF EXISTS wallet_transactions_are_immutable ON wallet_transactions;
      DROP TRIGGER IF EXISTS ledger_entries_are_immutable ON ledger_entries;
      DROP FUNCTION IF EXISTS validate_wallet_transaction_entries();
      DROP FUNCTION IF EXISTS prevent_wallet_transaction_financial_mutation();
      DROP FUNCTION IF EXISTS prevent_ledger_entry_mutation();
    SQL
  end
end
