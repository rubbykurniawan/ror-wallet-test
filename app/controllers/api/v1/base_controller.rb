require "digest"

module Api
  module V1
    class BaseController < ApplicationController
      before_action :authenticate_user!
      before_action :verify_csrf_token!, if: :state_changing_request?

      rescue_from StandardError, with: :render_internal_server_error
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from WalletTransactions::Forbidden, with: :render_forbidden
      rescue_from WalletTransactions::InvalidRequest, ActiveRecord::RecordInvalid, ActionController::ParameterMissing,
        with: :render_validation_error
      rescue_from WalletTransactions::InsufficientFunds, with: :render_insufficient_funds
      rescue_from WalletTransactions::IdempotencyConflict, with: :render_idempotency_conflict

      private

      attr_reader :current_user, :current_user_session

      def authenticate_user!
        raw_token = cookies[:wallet_session].to_s
        digest = Digest::SHA256.hexdigest(raw_token)
        @current_user_session = UserSession.includes(:user).find_by(token_digest: digest)
        unless raw_token.present? && @current_user_session&.active?
          return render_error("unauthorized", "Authentication required", :unauthorized)
        end

        @current_user = @current_user_session.user
      end

      def verify_csrf_token!
        cookie_token = cookies[:wallet_csrf].to_s
        header_token = request.headers["X-CSRF-Token"].to_s
        expected_digest = current_user_session.csrf_token_digest
        valid = cookie_token.present? && header_token.present? &&
          ActiveSupport::SecurityUtils.secure_compare(cookie_token, header_token) &&
          ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(header_token), expected_digest)
        return if valid

        render_error("csrf_invalid", "A valid CSRF token is required", :forbidden)
      end

      def state_changing_request?
        request.post? || request.put? || request.patch? || request.delete?
      end

      def render_validation_error(error)
        detail = error.respond_to?(:record) ? error.record.errors.full_messages : error.message
        render_error("validation_error", detail, :unprocessable_entity)
      end

      def render_forbidden(error)
        render_error("forbidden", error.message, :forbidden)
      end

      def render_insufficient_funds(error)
        render_error("insufficient_funds", error.message, :unprocessable_entity)
      end

      def render_idempotency_conflict(error)
        render_error("idempotency_conflict", error.message, :conflict)
      end

      def render_not_found(_error)
        render_error("not_found", "Resource not found", :not_found)
      end

      def render_internal_server_error(error)
        Rails.logger.error("Unhandled API exception request_id=#{request.request_id} error=#{error.class}")
        Rails.logger.error(error.backtrace.join("\n")) if error.backtrace.present?
        render_error("internal_server_error", "An unexpected error occurred. Please try again later.", :internal_server_error)
      end

      def render_error(code, message, status)
        render json: { error: { code: code, message: message } }, status: status
      end

      def money(amount)
        format("%.2f", amount)
      end

    end
  end
end
