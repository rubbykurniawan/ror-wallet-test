require "test_helper"

class AuthWalletApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "api@example.test", password: "correct horse battery staple")
    @other = User.create!(email: "other-api@example.test", password: "correct horse battery staple")
    @wallet = Wallet.create!(owner: @user, currency: "IDR")
    @other_wallet = Wallet.create!(owner: @other, currency: "IDR")
  end

  test "sign-in creates a session and provides the CSRF token; sign-out revokes it" do
    post "/api/v1/sign_in", params: { email: " API@EXAMPLE.TEST ", password: "correct horse battery staple" }, as: :json

    assert_response :created
    csrf_token = response.parsed_body.dig("data", "csrf_token")
    session_token = response.cookies["wallet_session"]
    assert csrf_token.present?
    assert session_token.present?
    assert UserSession.exists?(token_digest: Digest::SHA256.hexdigest(session_token))

    cookies["wallet_session"] = session_token
    get "/api/v1/me", as: :json
    assert_response :ok
    assert_equal @user.id, response.parsed_body.dig("data", "id")

    delete "/api/v1/sign_out", headers: { "X-CSRF-Token" => csrf_token }, as: :json
    assert_response :no_content
    assert UserSession.where(token_digest: Digest::SHA256.hexdigest(session_token)).first.revoked_at
  end

  test "invalid credentials and signup requests do not create users or sessions" do
    assert_no_difference("UserSession.count") do
      post "/api/v1/sign_in", params: { email: @user.email, password: "wrong" }, as: :json
    end
    assert_response :unauthorized

    assert_no_difference("User.count") do
      post "/api/v1/sign_up", params: { email: "new@example.test", password: "long enough password" }, as: :json
    end
    assert_response :not_found
  end

  test "wallet endpoints require an active session and CSRF token for writes" do
    get "/api/v1/wallets/#{@wallet.id}", as: :json
    assert_response :unauthorized

    csrf_token, session_token = sign_in
    cookies["wallet_session"] = session_token
    post "/api/v1/transactions/deposit",
      params: { target_wallet_id: @wallet.id, amount: "10.00" }, as: :json
    assert_response :forbidden

    post "/api/v1/transactions/deposit",
      params: { target_wallet_id: @wallet.id, amount: "10.00" },
      headers: { "X-CSRF-Token" => csrf_token, "Idempotency-Key" => "api-deposit" }, as: :json
    assert_response :created
    assert_equal "10.00", response.parsed_body.dig("data", "balance")
  end

  test "users may not inspect or debit another user's wallet" do
    csrf_token, session_token = sign_in
    cookies["wallet_session"] = session_token

    get "/api/v1/wallets/#{@other_wallet.id}", as: :json
    assert_response :not_found

    post "/api/v1/transactions/withdraw",
      params: { source_wallet_id: @other_wallet.id, amount: "1.00" },
      headers: { "X-CSRF-Token" => csrf_token, "Idempotency-Key" => "forbidden-withdraw" }, as: :json
    assert_response :forbidden
  end

  test "wallet reads return the same not-found response for foreign and missing wallet IDs" do
    _csrf_token, session_token = sign_in
    cookies["wallet_session"] = session_token

    get "/api/v1/wallets/#{@other_wallet.id}", as: :json
    assert_response :not_found
    foreign_wallet_response = response.parsed_body

    get "/api/v1/wallets/99999999", as: :json
    assert_response :not_found
    assert_equal foreign_wallet_response, response.parsed_body

    get "/api/v1/wallets/#{@other_wallet.id}/transactions", as: :json
    assert_response :not_found
    foreign_history_response = response.parsed_body

    get "/api/v1/wallets/99999999/transactions", as: :json
    assert_response :not_found
    assert_equal foreign_history_response, response.parsed_body
  end

  test "wallet history and transaction API expose derived balances and support transfer idempotency" do
    csrf_token, session_token = sign_in
    cookies["wallet_session"] = session_token
    headers = { "X-CSRF-Token" => csrf_token, "Idempotency-Key" => "seed-wallet" }
    post "/api/v1/transactions/deposit", params: { target_wallet_id: @wallet.id, amount: "50.00" }, headers: headers, as: :json
    assert_response :created

    transfer_headers = { "X-CSRF-Token" => csrf_token, "Idempotency-Key" => "api-transfer" }
    transfer_params = { source_wallet_id: @wallet.id, target_wallet_id: @other_wallet.id, amount: "12.50" }
    post "/api/v1/transactions/transfer", params: transfer_params, headers: transfer_headers, as: :json
    assert_response :created
    transfer_id = response.parsed_body.dig("data", "id")
    assert_equal "37.50", response.parsed_body.dig("data", "source_balance")
    assert_not response.parsed_body.fetch("data").key?("target_balance")
    assert_equal BigDecimal("12.50"), @other_wallet.reload.balance

    post "/api/v1/transactions/transfer", params: transfer_params, headers: transfer_headers, as: :json
    assert_response :created
    assert_equal transfer_id, response.parsed_body.dig("data", "id")
    assert_equal 2, WalletTransaction.count
    assert_equal 3, LedgerEntry.count

    get "/api/v1/wallets/#{@wallet.id}/transactions", as: :json
    assert_response :ok
    assert_equal 2, response.parsed_body.fetch("data").length
  end

  test "transfers may credit Team and Stock wallets without exposing their balances" do
    csrf_token, session_token = sign_in
    cookies["wallet_session"] = session_token
    team_wallet = Wallet.create!(owner: Team.create!(name: "Receiving Team"), currency: "IDR")
    stock_wallet = Wallet.create!(owner: Stock.create!(symbol: "RCVG"), currency: "IDR")

    post "/api/v1/transactions/deposit", params: { target_wallet_id: @wallet.id, amount: "20.00" },
      headers: { "X-CSRF-Token" => csrf_token, "Idempotency-Key" => "seed-multi-owner" }, as: :json
    assert_response :created

    [ [ team_wallet, "3.00", "team-target" ], [ stock_wallet, "4.00", "stock-target" ] ].each do |target, amount, key|
      post "/api/v1/transactions/transfer",
        params: { source_wallet_id: @wallet.id, target_wallet_id: target.id, amount: amount },
        headers: { "X-CSRF-Token" => csrf_token, "Idempotency-Key" => key }, as: :json

      assert_response :created
      assert_not response.parsed_body.fetch("data").key?("target_balance")
    end

    assert_equal BigDecimal("3.00"), team_wallet.reload.balance
    assert_equal BigDecimal("4.00"), stock_wallet.reload.balance
    assert_equal BigDecimal("13.00"), @wallet.reload.balance
  end

  test "API reports malformed amounts and changed idempotent payloads with stable codes" do
    csrf_token, session_token = sign_in
    cookies["wallet_session"] = session_token
    headers = { "X-CSRF-Token" => csrf_token, "Idempotency-Key" => "bad-amount" }

    post "/api/v1/transactions/deposit", params: { target_wallet_id: @wallet.id, amount: "1.001" }, headers: headers, as: :json
    assert_response :unprocessable_entity
    assert_equal "validation_error", response.parsed_body.dig("error", "code")

    headers["Idempotency-Key"] = "reused"
    post "/api/v1/transactions/deposit", params: { target_wallet_id: @wallet.id, amount: "1.00" }, headers: headers, as: :json
    assert_response :created
    post "/api/v1/transactions/deposit", params: { target_wallet_id: @wallet.id, amount: "2.00" }, headers: headers, as: :json
    assert_response :conflict
    assert_equal "idempotency_conflict", response.parsed_body.dig("error", "code")
  end

  test "deposit reports a missing target wallet as a validation error naming the field" do
    csrf_token, session_token = sign_in
    cookies["wallet_session"] = session_token

    post "/api/v1/transactions/deposit", params: { amount: "10.00" },
      headers: { "X-CSRF-Token" => csrf_token, "Idempotency-Key" => "missing-target" }, as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_error", response.parsed_body.dig("error", "code")
    assert_includes response.parsed_body.dig("error", "message"), "target_wallet_id"
  end

  test "unexpected API errors return a generic JSON response without internal details" do
    _csrf_token, session_token = sign_in
    cookies["wallet_session"] = session_token

    original_balance = Wallet.instance_method(:balance)
    Wallet.define_method(:balance) { raise RuntimeError, "internal database detail" }
    begin
      get "/api/v1/wallets/#{@wallet.id}", as: :json
    ensure
      Wallet.define_method(:balance, original_balance)
    end

    assert_response :internal_server_error
    assert_equal "internal_server_error", response.parsed_body.dig("error", "code")
    assert_equal "An unexpected error occurred. Please try again later.", response.parsed_body.dig("error", "message")
    assert_not_includes response.body, "internal database detail"
    assert_match %r{application/json}, response.media_type
  end

  test "expired and revoked sessions are rejected" do
    persist_test_session(token: "expired-token", expires_at: 1.minute.ago)
    cookies["wallet_session"] = "expired-token"
    get "/api/v1/me", as: :json
    assert_response :unauthorized

    persist_test_session(token: "revoked-token", expires_at: 1.hour.from_now, revoked_at: Time.current)
    cookies["wallet_session"] = "revoked-token"
    get "/api/v1/me", as: :json
    assert_response :unauthorized
  end

  private

  def sign_in
    post "/api/v1/sign_in", params: { email: @user.email, password: "correct horse battery staple" }, as: :json
    [ response.parsed_body.dig("data", "csrf_token"), response.cookies["wallet_session"] ]
  end

  def persist_test_session(token:, expires_at:, revoked_at: nil)
    UserSession.create!(
      user: @user,
      token_digest: Digest::SHA256.hexdigest(token),
      csrf_token_digest: Digest::SHA256.hexdigest("csrf-token"),
      expires_at: expires_at,
      revoked_at: revoked_at
    )
  end
end
