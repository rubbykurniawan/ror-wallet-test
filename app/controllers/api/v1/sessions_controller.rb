module Api
  module V1
    class SessionsController < BaseController
      skip_before_action :authenticate_user!, only: :create
      skip_before_action :verify_csrf_token!, only: :create

      def create
        user = User.find_by(email: params[:email].to_s.strip.downcase)
        unless user&.authenticate(params[:password].to_s)
          return render json: { error: { code: "unauthorized", message: "Email or password is incorrect" } }, status: :unauthorized
        end

        result = UserSessions::Create.call(user: user)
        cookie_options = {
          expires: result.session.expires_at,
          path: "/",
          secure: Rails.env.production?,
          same_site: :strict
        }
        cookies[:wallet_session] = cookie_options.merge(value: result.token, httponly: true)
        cookies[:wallet_csrf] = cookie_options.merge(value: result.csrf_token, httponly: false)

        render json: {
          data: {
            id: user.id,
            email: user.email,
            csrf_token: result.csrf_token,
            expires_at: result.session.expires_at.iso8601
          }
        }, status: :created
      end

      def show
        render json: { data: { id: current_user.id, email: current_user.email } }
      end

      def destroy
        current_user_session.revoke!
        cookies.delete(:wallet_session, path: "/")
        cookies.delete(:wallet_csrf, path: "/")
        head :no_content
      end
    end
  end
end
