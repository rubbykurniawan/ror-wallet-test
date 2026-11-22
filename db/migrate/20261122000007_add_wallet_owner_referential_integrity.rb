class AddWalletOwnerReferentialIntegrity < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION validate_wallet_owner_reference() RETURNS trigger AS $$
      BEGIN
        CASE NEW.owner_type
        WHEN 'User' THEN
          PERFORM 1 FROM users WHERE id = NEW.owner_id FOR KEY SHARE;
        WHEN 'Team' THEN
          PERFORM 1 FROM teams WHERE id = NEW.owner_id FOR KEY SHARE;
        WHEN 'Stock' THEN
          PERFORM 1 FROM stocks WHERE id = NEW.owner_id FOR KEY SHARE;
        ELSE
          RAISE EXCEPTION 'wallet owner type is not supported: %', NEW.owner_type
            USING ERRCODE = '23503';
        END CASE;

        IF NOT FOUND THEN
          RAISE EXCEPTION 'wallet owner does not exist: %.%', NEW.owner_type, NEW.owner_id
            USING ERRCODE = '23503';
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER wallets_owner_must_exist
      BEFORE INSERT OR UPDATE OF owner_type, owner_id ON wallets
      FOR EACH ROW EXECUTE FUNCTION validate_wallet_owner_reference();

      CREATE FUNCTION prevent_wallet_owner_orphaning() RETURNS trigger AS $$
      DECLARE
        owner_type_name text;
      BEGIN
        owner_type_name := CASE TG_TABLE_NAME
          WHEN 'users' THEN 'User'
          WHEN 'teams' THEN 'Team'
          WHEN 'stocks' THEN 'Stock'
        END;

        IF TG_OP = 'UPDATE' AND NEW.id IS NOT DISTINCT FROM OLD.id THEN
          RETURN NEW;
        END IF;

        IF EXISTS (
          SELECT 1 FROM wallets
          WHERE owner_type = owner_type_name AND owner_id = OLD.id
        ) THEN
          RAISE EXCEPTION 'wallet owner is referenced by a wallet: %.%', owner_type_name, OLD.id
            USING ERRCODE = '23503';
        END IF;

        IF TG_OP = 'DELETE' THEN
          RETURN OLD;
        END IF;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER users_with_wallets_cannot_be_deleted
      BEFORE DELETE ON users
      FOR EACH ROW EXECUTE FUNCTION prevent_wallet_owner_orphaning();
      CREATE TRIGGER users_with_wallets_cannot_change_id
      BEFORE UPDATE OF id ON users
      FOR EACH ROW EXECUTE FUNCTION prevent_wallet_owner_orphaning();

      CREATE TRIGGER teams_with_wallets_cannot_be_deleted
      BEFORE DELETE ON teams
      FOR EACH ROW EXECUTE FUNCTION prevent_wallet_owner_orphaning();
      CREATE TRIGGER teams_with_wallets_cannot_change_id
      BEFORE UPDATE OF id ON teams
      FOR EACH ROW EXECUTE FUNCTION prevent_wallet_owner_orphaning();

      CREATE TRIGGER stocks_with_wallets_cannot_be_deleted
      BEFORE DELETE ON stocks
      FOR EACH ROW EXECUTE FUNCTION prevent_wallet_owner_orphaning();
      CREATE TRIGGER stocks_with_wallets_cannot_change_id
      BEFORE UPDATE OF id ON stocks
      FOR EACH ROW EXECUTE FUNCTION prevent_wallet_owner_orphaning();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS stocks_with_wallets_cannot_change_id ON stocks;
      DROP TRIGGER IF EXISTS stocks_with_wallets_cannot_be_deleted ON stocks;
      DROP TRIGGER IF EXISTS teams_with_wallets_cannot_change_id ON teams;
      DROP TRIGGER IF EXISTS teams_with_wallets_cannot_be_deleted ON teams;
      DROP TRIGGER IF EXISTS users_with_wallets_cannot_change_id ON users;
      DROP TRIGGER IF EXISTS users_with_wallets_cannot_be_deleted ON users;
      DROP TRIGGER IF EXISTS wallets_owner_must_exist ON wallets;
      DROP FUNCTION IF EXISTS prevent_wallet_owner_orphaning();
      DROP FUNCTION IF EXISTS validate_wallet_owner_reference();
    SQL
  end
end
