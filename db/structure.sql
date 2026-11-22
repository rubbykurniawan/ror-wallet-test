SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: prevent_ledger_entry_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_ledger_entry_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'ledger entries are immutable'
    USING ERRCODE = '55000';
END;
$$;


--
-- Name: prevent_wallet_owner_orphaning(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_wallet_owner_orphaning() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: prevent_wallet_transaction_financial_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.prevent_wallet_transaction_financial_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM ledger_entries WHERE wallet_transaction_id = OLD.id) THEN
    RAISE EXCEPTION 'wallet transactions with ledger entries are immutable'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: validate_wallet_owner_reference(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_wallet_owner_reference() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: validate_wallet_transaction_entries(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validate_wallet_transaction_entries() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ledger_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ledger_entries (
    id bigint NOT NULL,
    wallet_id bigint NOT NULL,
    wallet_transaction_id bigint NOT NULL,
    amount numeric(20,2) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT ledger_entry_amount_nonzero CHECK ((amount <> (0)::numeric))
);


--
-- Name: ledger_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ledger_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ledger_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ledger_entries_id_seq OWNED BY public.ledger_entries.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: stocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stocks (
    id bigint NOT NULL,
    symbol character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: stocks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stocks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stocks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stocks_id_seq OWNED BY public.stocks.id;


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id bigint NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: teams_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.teams_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: teams_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.teams_id_seq OWNED BY public.teams.id;


--
-- Name: user_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_sessions (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    token_digest character varying(64) NOT NULL,
    csrf_token_digest character varying(64) NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: user_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.user_sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: user_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.user_sessions_id_seq OWNED BY public.user_sessions.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email character varying NOT NULL,
    password_digest character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: wallet_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallet_transactions (
    id bigint NOT NULL,
    transaction_type character varying NOT NULL,
    actor_id bigint NOT NULL,
    source_wallet_id bigint,
    target_wallet_id bigint,
    amount numeric(20,2) NOT NULL,
    idempotency_key character varying NOT NULL,
    request_fingerprint character varying(64) NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT wallet_transaction_amount_positive CHECK ((amount > (0)::numeric)),
    CONSTRAINT wallet_transaction_type_valid CHECK (((transaction_type)::text = ANY (ARRAY[('deposit'::character varying)::text, ('withdraw'::character varying)::text, ('transfer'::character varying)::text]))),
    CONSTRAINT wallet_transaction_wallet_direction_valid CHECK (((((transaction_type)::text = 'deposit'::text) AND (source_wallet_id IS NULL) AND (target_wallet_id IS NOT NULL)) OR (((transaction_type)::text = 'withdraw'::text) AND (source_wallet_id IS NOT NULL) AND (target_wallet_id IS NULL)) OR (((transaction_type)::text = 'transfer'::text) AND (source_wallet_id IS NOT NULL) AND (target_wallet_id IS NOT NULL) AND (source_wallet_id <> target_wallet_id))))
);


--
-- Name: wallet_transactions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wallet_transactions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wallet_transactions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wallet_transactions_id_seq OWNED BY public.wallet_transactions.id;


--
-- Name: wallets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallets (
    id bigint NOT NULL,
    owner_type character varying NOT NULL,
    owner_id bigint NOT NULL,
    currency character varying DEFAULT 'IDR'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT wallet_currency_is_idr CHECK (((currency)::text = 'IDR'::text))
);


--
-- Name: wallets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.wallets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: wallets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.wallets_id_seq OWNED BY public.wallets.id;


--
-- Name: ledger_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries ALTER COLUMN id SET DEFAULT nextval('public.ledger_entries_id_seq'::regclass);


--
-- Name: stocks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stocks ALTER COLUMN id SET DEFAULT nextval('public.stocks_id_seq'::regclass);


--
-- Name: teams id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams ALTER COLUMN id SET DEFAULT nextval('public.teams_id_seq'::regclass);


--
-- Name: user_sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions ALTER COLUMN id SET DEFAULT nextval('public.user_sessions_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: wallet_transactions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions ALTER COLUMN id SET DEFAULT nextval('public.wallet_transactions_id_seq'::regclass);


--
-- Name: wallets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets ALTER COLUMN id SET DEFAULT nextval('public.wallets_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: ledger_entries ledger_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT ledger_entries_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: stocks stocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stocks
    ADD CONSTRAINT stocks_pkey PRIMARY KEY (id);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: user_sessions user_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: wallet_transactions wallet_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_pkey PRIMARY KEY (id);


--
-- Name: wallets wallets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_pkey PRIMARY KEY (id);


--
-- Name: idx_ledger_entries_transaction_wallet_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_ledger_entries_transaction_wallet_unique ON public.ledger_entries USING btree (wallet_transaction_id, wallet_id);


--
-- Name: idx_wallet_transactions_actor_idempotency_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_wallet_transactions_actor_idempotency_unique ON public.wallet_transactions USING btree (actor_id, idempotency_key);


--
-- Name: idx_wallets_owner_currency_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_wallets_owner_currency_unique ON public.wallets USING btree (owner_type, owner_id, currency);


--
-- Name: index_ledger_entries_on_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_entries_on_wallet_id ON public.ledger_entries USING btree (wallet_id);


--
-- Name: index_ledger_entries_on_wallet_transaction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ledger_entries_on_wallet_transaction_id ON public.ledger_entries USING btree (wallet_transaction_id);


--
-- Name: index_stocks_on_symbol; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stocks_on_symbol ON public.stocks USING btree (symbol);


--
-- Name: index_user_sessions_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_user_sessions_on_token_digest ON public.user_sessions USING btree (token_digest);


--
-- Name: index_user_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_user_sessions_on_user_id ON public.user_sessions USING btree (user_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_wallet_transactions_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wallet_transactions_on_actor_id ON public.wallet_transactions USING btree (actor_id);


--
-- Name: index_wallet_transactions_on_source_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wallet_transactions_on_source_wallet_id ON public.wallet_transactions USING btree (source_wallet_id);


--
-- Name: index_wallet_transactions_on_target_wallet_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wallet_transactions_on_target_wallet_id ON public.wallet_transactions USING btree (target_wallet_id);


--
-- Name: ledger_entries ledger_entries_are_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ledger_entries_are_immutable BEFORE DELETE OR UPDATE ON public.ledger_entries FOR EACH ROW EXECUTE FUNCTION public.prevent_ledger_entry_mutation();


--
-- Name: ledger_entries ledger_entries_match_transaction; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER ledger_entries_match_transaction AFTER INSERT ON public.ledger_entries DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_wallet_transaction_entries();


--
-- Name: stocks stocks_with_wallets_cannot_be_deleted; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER stocks_with_wallets_cannot_be_deleted BEFORE DELETE ON public.stocks FOR EACH ROW EXECUTE FUNCTION public.prevent_wallet_owner_orphaning();


--
-- Name: stocks stocks_with_wallets_cannot_change_id; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER stocks_with_wallets_cannot_change_id BEFORE UPDATE OF id ON public.stocks FOR EACH ROW EXECUTE FUNCTION public.prevent_wallet_owner_orphaning();


--
-- Name: teams teams_with_wallets_cannot_be_deleted; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER teams_with_wallets_cannot_be_deleted BEFORE DELETE ON public.teams FOR EACH ROW EXECUTE FUNCTION public.prevent_wallet_owner_orphaning();


--
-- Name: teams teams_with_wallets_cannot_change_id; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER teams_with_wallets_cannot_change_id BEFORE UPDATE OF id ON public.teams FOR EACH ROW EXECUTE FUNCTION public.prevent_wallet_owner_orphaning();


--
-- Name: users users_with_wallets_cannot_be_deleted; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER users_with_wallets_cannot_be_deleted BEFORE DELETE ON public.users FOR EACH ROW EXECUTE FUNCTION public.prevent_wallet_owner_orphaning();


--
-- Name: users users_with_wallets_cannot_change_id; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER users_with_wallets_cannot_change_id BEFORE UPDATE OF id ON public.users FOR EACH ROW EXECUTE FUNCTION public.prevent_wallet_owner_orphaning();


--
-- Name: wallet_transactions wallet_transactions_are_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER wallet_transactions_are_immutable BEFORE UPDATE OF transaction_type, actor_id, source_wallet_id, target_wallet_id, amount, idempotency_key, request_fingerprint ON public.wallet_transactions FOR EACH ROW EXECUTE FUNCTION public.prevent_wallet_transaction_financial_mutation();


--
-- Name: wallet_transactions wallet_transactions_have_valid_entries; Type: TRIGGER; Schema: public; Owner: -
--

CREATE CONSTRAINT TRIGGER wallet_transactions_have_valid_entries AFTER INSERT ON public.wallet_transactions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.validate_wallet_transaction_entries();


--
-- Name: wallets wallets_owner_must_exist; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER wallets_owner_must_exist BEFORE INSERT OR UPDATE OF owner_type, owner_id ON public.wallets FOR EACH ROW EXECUTE FUNCTION public.validate_wallet_owner_reference();


--
-- Name: wallet_transactions fk_rails_55791654ce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT fk_rails_55791654ce FOREIGN KEY (source_wallet_id) REFERENCES public.wallets(id);


--
-- Name: ledger_entries fk_rails_5755d43d41; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT fk_rails_5755d43d41 FOREIGN KEY (wallet_transaction_id) REFERENCES public.wallet_transactions(id);


--
-- Name: ledger_entries fk_rails_98acf6cd6c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ledger_entries
    ADD CONSTRAINT fk_rails_98acf6cd6c FOREIGN KEY (wallet_id) REFERENCES public.wallets(id);


--
-- Name: user_sessions fk_rails_9fa262d742; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT fk_rails_9fa262d742 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: wallet_transactions fk_rails_b8e75f7451; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT fk_rails_b8e75f7451 FOREIGN KEY (target_wallet_id) REFERENCES public.wallets(id);


--
-- Name: wallet_transactions fk_rails_d181432c3e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT fk_rails_d181432c3e FOREIGN KEY (actor_id) REFERENCES public.users(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261122000007'),
('20261121000006'),
('20261121000005'),
('20261121000004'),
('20261121000003'),
('20261121000002'),
('20261121000001');
