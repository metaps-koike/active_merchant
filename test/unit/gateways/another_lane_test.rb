# coding: utf-8
require 'test_helper'

class AnotherLaneTest < Test::Unit::TestCase
  def setup
    @gateway = AnotherLaneGateway.new(
      site_id: 'test',
      site_password: 'test'
    )

    @credit_card = credit_card('4000000000000000')
    @amount = 210

    @transaction_id = '1403068209641'

    @options = {
      customer_id: 'customer_id',
      customer_password: 'password',
      mail: 'example@example.com',
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_get).times(2).returns(successful_authorize_response).then.returns(successful_capture_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response

    assert_equal '1403068210744', response.authorization
    assert response.test?
  end


  def test_successful_quick_purchase
    @gateway.expects(:ssl_get).times(2).returns(successful_authorize_response).then.returns(successful_capture_response)

    response = @gateway.purchase(@amount, nil, @options)
    assert_success response

    assert_equal '1403068210744', response.authorization
    assert response.test?
  end


  def test_successful_authorize
    @gateway.expects(:ssl_get).returns(successful_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response

    assert_equal '1403068210743', response.authorization
    assert response.test?
  end


  def test_successful_authorize_capture

    @gateway.expects(:ssl_get).returns(successful_authorize_response)

    response = @gateway.authorize(@amount, @credit_card, @options)
    assert_success response

    assert_equal '1403068210743', response.authorization
    assert response.test?


    @gateway.expects(:ssl_get).returns(successful_capture_response)

    response = @gateway.capture(@amount, response.authorization)
    assert_success response

    assert_equal '1403068210744', response.authorization
    assert response.test?
  end


  def test_failed_purchase

    @gateway.expects(:ssl_get).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert response.test?

  end


  def test_successful_update
    @gateway.expects(:ssl_get).returns(successful_customer_response)

    response = @gateway.update(@options[:customer_id], @options[:customer_password], @credit_card, nil, @options)
    assert_success response
    assert response.test?

  end


  def test_successful_update_mail
    @gateway.expects(:ssl_get).returns(successful_purchase_response)

    response = @gateway.update(@options[:customer_id], @options[:customer_password], nil, 'new-' + @options[:mail], @options)
    assert_success response
    assert response.test?

  end


  def test_successful_void
    @gateway.expects(:ssl_get).returns(successful_get_status_response)

    response = @gateway.void(@transaction_id)
    assert_success response

    assert_equal '1403068210742', response.authorization
    assert response.test?
  end


  private

  def successful_purchase_response
    'state=1&TransactionId=1403068210742&msg=Approved'
  end

  def successful_authorize_response
    'state=1&TransactionId=1403068210743&msg=Approved'
  end

  def successful_capture_response
    'state=1&TransactionId=1403068210744&msg=Approved'
  end

  def failed_purchase_response
    'state=2&msg=CARD NO CANNOT BE USED.'
  end

  def successful_customer_response
    'state=1&msg=ｱﾘｶﾞﾄｳ ｺﾞｻﾞｲﾏｼﾀ(thanks)'
  end

  def successful_get_status_response
    'state=1&TransactionId=1403068210742&TransactionState=CANCEL&msg='
  end

  def successful_void_response
    'state=1&TransactionId=1403068210742&TransactionState=CANCEL&msg='
  end

end
