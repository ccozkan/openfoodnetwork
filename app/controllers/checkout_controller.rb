require 'open_food_network/address_finder'

class CheckoutController < Spree::StoreController
  layout 'darkswarm'

  include CheckoutHelper
  include OrderCyclesHelper
  include EnterprisesHelper

  ssl_required

  # We need pessimistic locking to avoid race conditions.
  # Otherwise we fail on duplicate indexes or end up with negative stock.
  prepend_around_filter CurrentOrderLocker, only: :update

  prepend_before_filter :check_hub_ready_for_checkout
  prepend_before_filter :check_order_cycle_expiry
  prepend_before_filter :require_order_cycle
  prepend_before_filter :require_distributor_chosen

  before_filter :load_order

  before_filter :ensure_order_not_completed
  before_filter :ensure_checkout_allowed
  before_filter :ensure_sufficient_stock_lines

  before_filter :associate_user
  before_filter :check_authorization
  before_filter :enable_embedded_shopfront

  helper 'spree/orders'

  rescue_from Spree::Core::GatewayError, with: :rescue_from_spree_gateway_error

  def edit
    # This is only required because of spree_paypal_express. If we implement
    # a version of paypal that uses this controller, and more specifically
    # the #update_failed method, then we can remove this call
    RestartCheckout.new(@order).call
  end

  def update
    shipping_method_id = object_params.delete(:shipping_method_id)

    return update_failed unless @order.update_attributes(object_params)

    fire_event('spree.checkout.update')

    while @order.state != "complete"
      if @order.state == "payment"
        return if redirect_to_paypal_express_form_if_needed
      end

      if @order.state == "delivery"
        @order.select_shipping_method(shipping_method_id)
      end

      next if advance_order_state(@order)

      flash[:error] = if @order.errors.present?
                        @order.errors.full_messages.to_sentence
                      else
                        t(:payment_processing_failed)
                      end
      update_failed
      return
    end
    return update_failed unless @order.state == "complete" || @order.completed?

    set_default_bill_address
    set_default_ship_address

    ResetOrderService.new(self, current_order).call
    session[:access_token] = current_order.token

    flash[:notice] = t(:order_processed_successfully)
    respond_to do |format|
      format.html do
        respond_with(@order, location: order_path(@order))
      end
      format.json do
        render json: { path: order_path(@order) }, status: :ok
      end
    end
  rescue Spree::Core::GatewayError => e
    # This is done for all actions in the Spree::CheckoutController.
    rescue_from_spree_gateway_error(e)
  rescue StandardError => e
    Bugsnag.notify(e)
    flash[:error] = I18n.t("checkout.failed")
    update_failed
  end

  # Clears the cached order. Required for #current_order to return a new order
  # to serve as cart. See https://github.com/spree/spree/blob/1-3-stable/core/lib/spree/core/controller_helpers/order.rb#L14
  # for details.
  def expire_current_order
    session[:order_id] = nil
    @current_order = nil
  end

  private

  def check_authorization
    authorize!(:edit, current_order, session[:access_token])
  end

  def ensure_checkout_allowed
    redirect_to main_app.cart_path unless @order.checkout_allowed?
  end

  def ensure_order_not_completed
    redirect_to main_app.cart_path if @order.completed?
  end

  def ensure_sufficient_stock_lines
    if @order.insufficient_stock_lines.present?
      flash[:error] = Spree.t(:inventory_error_flash_for_insufficient_quantity)
      redirect_to main_app.cart_path
    end
  end

  def set_default_bill_address
    if params[:order][:default_bill_address]
      new_bill_address = @order.bill_address.clone.attributes

      user_bill_address_id = spree_current_user.bill_address.andand.id
      spree_current_user.update_attributes(
        bill_address_attributes: new_bill_address.merge('id' => user_bill_address_id)
      )

      customer_bill_address_id = @order.customer.bill_address.andand.id
      @order.customer.update_attributes(
        bill_address_attributes: new_bill_address.merge('id' => customer_bill_address_id)
      )
    end
  end

  def set_default_ship_address
    if params[:order][:default_ship_address]
      new_ship_address = @order.ship_address.clone.attributes

      user_ship_address_id = spree_current_user.ship_address.andand.id
      spree_current_user.update_attributes(
        ship_address_attributes: new_ship_address.merge('id' => user_ship_address_id)
      )

      customer_ship_address_id = @order.customer.ship_address.andand.id
      @order.customer.update_attributes(
        ship_address_attributes: new_ship_address.merge('id' => customer_ship_address_id)
      )
    end
  end

  # Copied and modified from spree. Remove check for order state, since the state machine is
  # progressed all the way in one go with the one page checkout.
  def object_params
    # For payment step, filter order parameters to produce the expected
    #   nested attributes for a single payment and its source,
    #   discarding attributes for payment methods other than the one selected
    if params[:payment_source].present? && source_params = params.delete(:payment_source)[params[:order][:payments_attributes].first[:payment_method_id].underscore]
      params[:order][:payments_attributes].first[:source_attributes] = source_params
    end
    if params[:order][:payments_attributes]
      params[:order][:payments_attributes].first[:amount] = @order.total
    end
    if params[:order][:existing_card_id]
      construct_saved_card_attributes
    end
    params[:order]
  end

  # Perform order.next, guarding against StaleObjectErrors
  def advance_order_state(order)
    tries ||= 3
    order.next
  rescue ActiveRecord::StaleObjectError
    retry unless (tries -= 1).zero?
    false
  end

  def update_failed
    current_order.updater.shipping_address_from_distributor
    RestartCheckout.new(@order).call

    respond_to do |format|
      format.html do
        render :edit
      end
      format.json do
        render json: { errors: @order.errors, flash: flash.to_hash }.to_json, status: :bad_request
      end
    end
  end

  def load_order
    @order = current_order
    redirect_to(main_app.shop_path) && return unless @order && @order.checkout_allowed?
    redirect_to_cart_path && return unless valid_order_line_items?
    redirect_to(main_app.shop_path) && return if @order.completed?
    before_address
    setup_for_current_state
  end

  def setup_for_current_state
    method_name = :"before_#{@order.state}"
    __send__(method_name) if respond_to?(method_name, true)
  end

  def before_address
    associate_user

    finder = OpenFoodNetwork::AddressFinder.new(@order.email, @order.customer, spree_current_user)

    @order.bill_address = finder.bill_address
    @order.ship_address = finder.ship_address
  end

  def before_delivery
    return if params[:order].present?

    packages = @order.shipments.map(&:to_package)
    @differentiator = Spree::Stock::Differentiator.new(@order, packages)
  end

  def before_payment
    current_order.payments.destroy_all if request.put?
  end

  def valid_order_line_items?
    @order.insufficient_stock_lines.empty? &&
      OrderCycleDistributedVariants.new(@order.order_cycle, @order.distributor).
        distributes_order_variants?(@order)
  end

  def redirect_to_cart_path
    respond_to do |format|
      format.html do
        redirect_to main_app.cart_path
      end

      format.json do
        render json: { path: main_app.cart_path }, status: :bad_request
      end
    end
  end

  def redirect_to_paypal_express_form_if_needed
    return unless params[:order][:payments_attributes]

    payment_method_id = params[:order][:payments_attributes].first[:payment_method_id]
    payment_method = Spree::PaymentMethod.find(payment_method_id)
    return unless payment_method.is_a?(Spree::Gateway::PayPalExpress)

    render json: { path: spree.paypal_express_path(payment_method_id: payment_method.id) },
           status: :ok
    true
  end

  def construct_saved_card_attributes
    existing_card_id = params[:order].delete(:existing_card_id)
    return if existing_card_id.blank?

    credit_card = Spree::CreditCard.find(existing_card_id)
    if credit_card.try(:user_id).blank? || credit_card.user_id != spree_current_user.try(:id)
      raise Spree::Core::GatewayError, I18n.t(:invalid_credit_card)
    end

    # Not currently supported but maybe we should add it...?
    credit_card.verification_value = params[:cvc_confirm] if params[:cvc_confirm].present?

    params[:order][:payments_attributes].first[:source] = credit_card
    params[:order][:payments_attributes].first.delete :source_attributes
  end

  def rescue_from_spree_gateway_error(error)
    flash[:error] = t(:spree_gateway_error_flash_for_checkout, error: error.message)
    respond_to do |format|
      format.html { render :edit }
      format.json { render json: { flash: flash.to_hash }, status: :bad_request }
    end
  end
end
