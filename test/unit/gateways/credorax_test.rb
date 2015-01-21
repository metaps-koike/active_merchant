require 'test_helper'

class CredoraxTest < Test::Unit::TestCase
  def setup
    @gateway = CredoraxGateway.new(
      merchant_id: 'one_per_currency',
      md5_cipher_key: 'md5_cipher_key'
    )

    @credit_card = credit_card('4037660000001115', {:brand => 'visa', :verification_value => '123'})
    @amount = 100

    @options = {
      order_id: generate_unique_id,
      billing_address: address,
      description: 'Store Purchase'
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    @options[:ip] = '1.1.1.1' # Fake IP for tests
    @options[:email] = 'noone@example.com'

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response

    assert_equal 'REPLACE', response.authorization
    assert response.test?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    @options[:ip] = '0.0.0.0' # Fake IP for tests
    @options[:email] = 'noone@example.com'

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], response.error_code
  end

  def test_successful_authorize
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    @options[:ip] = '1.1.1.1' # Fake IP for tests
    @options[:email] = 'noone@example.com'

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response

    assert_equal 'REPLACE', response.authorization
    assert response.test?
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_authorize_response)

    @options[:ip] = '0.0.0.0' # Fake IP for tests
    @options[:email] = 'noone@example.com'

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], response.error_code
  end

  def test_successful_capture
    @gateway.expects(:ssl_post).returns(successful_capture_response)

    @options[:ip] = '1.1.1.1' # Fake IP for tests

    authorisation = 'TODO' # TODO
    response = @gateway.capture(nil, authorisation, @options)
    assert_success response

    assert_equal 'REPLACE', response.authorization
    assert response.test?
  end

  def test_failed_capture
    @gateway.expects(:ssl_post).returns(failed_capture_response)

    @options[:ip] = '0.0.0.0' # Fake IP for tests

    authorisation = 'TODO' # TODO
    response = @gateway.capture(nil, authorisation, @options)
    assert_failure response
    assert_equal Gateway::STANDARD_ERROR_CODE[:card_declined], response.error_code # TODO
  end

  def test_successful_refund
  end

  def test_failed_refund
  end

  def test_successful_void
  end

  def test_failed_void
  end

  def test_successful_verify
  end

  def test_successful_verify_with_failed_void
  end

  def test_failed_verify
  end

  private

  def successful_purchase_response
    %(
      Easy to capture by setting the DEBUG_ACTIVE_MERCHANT environment variable
      to "true" when running remote tests:

      $ DEBUG_ACTIVE_MERCHANT=true ruby -Itest \
        test/remote/gateways/remote_credorax_test.rb \
        -n test_successful_purchase
    )
  end

  def failed_purchase_response
  end

  def successful_authorize_response
  end

  def failed_authorize_response
  end

  def successful_capture_response
  end

  def failed_capture_response
  end

  def successful_refund_response
  end

  def failed_refund_response
  end

  def successful_void_response
  end

  def failed_void_response
  end
end
