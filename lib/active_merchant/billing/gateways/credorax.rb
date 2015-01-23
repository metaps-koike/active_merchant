module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class CredoraxGateway < Gateway

      ACTIONS = {
          sale:                         '1',
          authorisation:                '2',
          capture:                      '3',
          authorisation_void:           '4',
          capture_void:                 '9',
          create_token:                 '10',
          use_token_sale:               '11',
          use_token_auth:               '12',
          use_token_capture:            '13',
          token_auth_void:              '14',
          token_referral_credit:        '15',
      }

      TRANSACTION_TYPES = {
        first_recurring:                '1',
        subsequent_recurring:           '2',
        first_instalment:               '3',
        subsequent_instalment:          '4',
        card_only_calidation:           '5',
        straight_sale:                  '6'
      }

      # Codes returned in the 'z2' response parameter
      RESULT_CODES = {
        missing_valid_3d_secure_data:         '-13',
        missing_card_secure_code:             '-12',
        currency_not_supported_by_merchant:   '-11',
        unclassified_error:                   '-10',
        parameter_malformed:                  '-9',
        package_signature_malformed:          '-8',
        no_response_from_gateway:             '-7',
        transaction_rejected:                 '-5',
        account_status_not_updated:           '-3',
        account_does_not_exist:               '-2',
        account_already_exists:               '-1',
        success:                              '0',
        transaction_denied:                   '1',
        transaction_denied_high_fraud_risk:   '2',
        transaction_denied_high_avs_risk:     '03',
        transaction_denied_interchange_timeout: '04',
        transaction_declined:                 '05',
        redirect_url_issued:                  '7',
        transaction_denied_luhn_check_fail:   '9',
        transaction_partially_approved:       '10',
        transaction_3d_enrolled:              '100'
      }

      self.test_url = 'https://intconsole.credorax.com/intenv/service/gateway'
      self.live_url = 'https://example.com/live' # TODO

      self.supported_countries = ['US', 'JP', 'CA', 'GB'] # TODO
      self.default_currency = 'EUR' # TODO
      self.supported_cardtypes = [:visa, :master] # TODO

      self.homepage_url = 'http://epower.credorax.com'
      self.display_name = 'Credorax'

      STANDARD_ERROR_CODE_MAPPING = {}

      def initialize(options={})
        requires!(options, :md5_cipher_key, :merchant_id, :name_on_statement)
        super
      end

      def purchase(money, payment, options={})

        if payment.is_a?(ActiveMerchant::Billing::CreditCard)
          requires!(options, :email, :ip, :order_id, :description)
          # Sale
          post = {
              'O' => ACTIONS[:sale],                  # Operation Code
          }
          add_request_id(post, options)
          add_payment(post, payment)                  # Card information
          add_invoice(post, money, options)           # Item information
          add_customer_data(post, options)
          add_billing_address_data(post, options)     # Billing Address Info
        else
          # Use Token Sale
          requires!(options, :ip, :order_id, :description)
          post = {
              'O' => ACTIONS[:use_token_sale],        # Operation Code
          }
          add_token(post, payment)
          add_request_id(post, options)
          add_invoice(post, money, options)           # Item information
          add_customer_data(post, options)
        end
        commit(post)
      end

      def authorize(money, payment, options={})
        # Credit will be supplied in payment
        if payment.is_a?(ActiveMerchant::Billing::CreditCard)
          # Authorisation
          requires!(options, :email, :ip, :order_id)
          post = {
              'O' => ACTIONS[:authorisation],         # Operation Code
          }
          add_request_id(post, options)
          add_payment(post, payment)                  # Card information
          add_invoice(post, money, options)           # Item information
          add_customer_data(post, options)
          add_billing_address_data(post, options)     # Billing Address Info
        else
          # Use Token - Auth
          requires!(options, :ip, :order_id)
          post = {
              'O' => ACTIONS[:use_token_auth],     # Operation Code
          }
          add_request_id(post, options)
          add_token(post, payment)
          add_invoice(post, money, options)           # Item information
          add_customer_data(post, options)
          add_billing_address_data(post, options)     # Billing Address Info
        end

        commit(post)
      end

      def capture(money, authorization, options={})

        if authorization.has_key?(:token) && !authorization[:token].blank?
          # Use Token - Capture
          requires!(options, :ip, :order_id)
          post = {
              'O' => ACTIONS[:use_token_capture],  # Operation Code
          }
          add_request_id(post, options)
          add_token(post, authorization[:token])
          add_customer_data(post, options)
          add_invoice(post, money, options)           # Item information - We allow partial amounts
          add_previous_request_data(post, authorization)
        else
          # Capture
          requires!(options, :ip, :order_id)
          post = {
              'O' => ACTIONS[:capture],               # Operation Code
          }
          add_request_id(post, options)
          add_customer_data(post, options)
          add_invoice(post, money, options)           # Item information - We allow partial amounts
          add_previous_request_data(post, authorization)
        end

        commit(post)
      end

      def refund(money, authorization, options={})

        if authorization.has_key?(:token) && !authorization[:token].blank?
          # Token Referral Credit
          requires!(options, :ip, :order_id)
          post = {
              'O' => ACTIONS[:token_referral_credit], # Operation Code
          }
          add_request_id(post, options)
          add_token(post, authorization[:token])
          add_invoice(post, money, options)           # Item information
          add_customer_data(post, options)
          add_previous_request_data(post, authorization)
        else

          # Capture Void
          requires!(options, :ip, :order_id)
          post = {
              'O' => ACTIONS[:capture_void],          # Operation Code
          }
          add_request_id(post, options)
          add_customer_data(post, options)
          add_invoice(post, nil, options)             # Item information
          add_previous_request_data(post, authorization)
        end
        commit(post)
      end

      def void(authorization, options={})

        if authorization.has_key?(:token) && !authorization[:token].blank?
          # Token Auth Void
          requires!(options, :ip, :order_id)
          post = {
              'O' => ACTIONS[:token_auth_void],       # Operation Code
          }
          add_token(post, authorization[:token])
          add_request_id(post, options)
          add_customer_data(post, options)
          add_previous_request_data(post, authorization)
        else
          # Authorisation Void
          requires!(options, :ip, :order_id)
          post = {
              'O' => ACTIONS[:authorisation_void],    # Operation Code
          }
          add_request_id(post, options)
          add_customer_data(post, options)
          add_previous_request_data(post, authorization)
        end

        commit(post)
      end

      def store(payment, options = {})

        if payment.is_a?(ActiveMerchant::Billing::CreditCard)
          requires!(options, :ip, :order_id, :email)
          post = {
              'O' => ACTIONS[:create_token],       # Operation Code
          }
          add_request_id(post, options)
          add_invoice(post, 100, options) # Hard coded amount value, as it gets ignore by Credorax (it always returns a4=5 (500) in response)
          add_payment(post, payment)
          add_customer_data(post, options)
        else
          raise ArgumentError, 'payment must be a Credit card (ActiveMerchant::Billing::CreditCard)'
        end

        commit(post)

      end

      def verify(credit_card, options={})
        raise NotImplementedError, 'verify operation is not supported'
      end

      private

      def add_request_id(post, options)
        post['a1'] = options[:order_id]             # This must be unique across ALL API calls per Merchant
      end

      def add_token(post, token)
        unless token.nil?
          post['g1'] = token # Use token supplied, not generate one
        end
      end

      def add_previous_request_data(post, authorization)
        post['g2'] = authorization[:response_id]          # Previous Response ID
        post['g3'] = authorization[:authorization_code]   # Previous Authorisation code
        post['g4'] = authorization[:previous_request_id]  # Previous Request ID
      end

      def add_customer_data(post, options)
        if options.has_key? :email
          post['c3'] = options[:email]              # Billing Email Address
        end
        if options.has_key? :ip
          post['d1'] = options[:ip]                 # User's IP
        end
      end

      def add_billing_address_data(data, options)
        billing_address = options[:billing_address] || options[:address]
        if billing_address
          # TODO - Correct Mapping for c4 - Billing Street Number and c5 - Billing Street Name
          if billing_address.has_key? :city
            data['c7'] = billing_address[:city] # Billing City Name
          end
          if billing_address.has_key? :state
            if billing_address[:state].length > 3
              raise ArgumentError, 'state must be Subdivision Code (ISO-3166-2), max length 3 alphanumeric characters'
            end
            data['c8'] = billing_address[:state] # Billing Country Subdivision Code (ISO-3166-2)
          end
          if billing_address.has_key? :country
            data['c9'] = billing_address[:country] # Billing Country Code (ISO-3166)
          end
          if billing_address.has_key? :zip
            data['c10'] = billing_address[:zip] # Billing Country PostCode
          end
        end
      end

      def add_invoice(post, money, options)

        unless money.nil?
          post['a4'] = amount(money).to_i.to_s        # Billing Amount - Whole numbers (cents) as string
        end

        if options.has_key? :description
          if options[:description].length > 13
            raise ArgumentError, 'transaction description can has maximum length of 13 characters'
          end
          post['i2'] = "#{@options[:name_on_statement]}*#{options[:description]}" # Transaction Description
        end

        if options.has_key? :invoice
          post['a8'] = options[:invoice] # Merchant invoice ID
        end

      end

      def add_payment(post, payment)
        post['b1'] = payment.number                 # Card Number
        post['b2'] = card_brand_code(payment.brand) # Card Type ID
        post['b3'] = '%02d' % payment.month         # Card Expiration Month (MM) - ActiveMerchant Card stores as FixNum
        post['b4'] = payment.year.to_s[-2..-1]      # Card Expiration Year (YY) - ActiveMerchant Card stores as FixNum
        post['b5'] = payment.verification_value     # Card Secure Code, Visa
        post['c1'] = payment.name                   # Billing Contact Name
      end

      def parse(body)
        results = {}
        body.split(/&/).each do |pair|
          key,val = pair.split(/=/)
          results[key] = val
        end
        results
      end

      def commit(parameters)

        url = (test? ? test_url : live_url)

        # Add Merchant ID, then create the MD5 message and add to parameters
        parameters['M'] = @options[:merchant_id]    # MerchantID
        parameters['K'] = create_md5_message(parameters, @options[:md5_cipher_key])

        response = parse(ssl_post(url, post_data(parameters)))

        Response.new(
          success_from(response),
          message_from(response),
          response,
          {
              authorization: authorization_from(response),
              test: test?,
              cvv_result: cvv_result_from(response),
              avs_response: avs_result_from(response),
              error_code: result_code_from(response)
          }
        )
      end

      def success_from(response)
        result_code_from(response) == '0'
      end

      def result_code_from(response)
        response['z2'].to_s
      end

      def message_from(response)
        response['z3']
      end

      def authorization_from(response)
        auth = {
          authorization_code: response['z4'],
          response_id: response['z1'],
          transaction_id: response['z13'],
          previous_request_id: response['a1']
        }
        unless response['g1'].blank?
          auth[:token] = response['g1']
        end
        auth
      end

      def cvv_result_from(response)
        response['z14']
      end

      def avs_result_from(response)
        response['z9']
      end

      def post_data(parameters = {})
        post = {}
        request = post.merge(parameters).map {|key,value| "#{key}=#{CGI.escape(value.to_s)}"}.join("&")
        request
      end

      def create_md5_message(data, signature_key)

        # Sort the parameters in alphabetical order (parameters which are capitalised should come first):
        sorted_keys = data.keys.sort

        # For each parameter value replace any special characters < > “ ‘ ( ) \ with spaces
        # For each parameter value remove any leading and trailing spaces
        normalized_values = sorted_keys.map do |key|
          data[key].gsub(/[<>“‘\(\)\\]/, '').strip
        end

        # Line up all parameter values in the same order.
        line_up_value = normalized_values.join

        # Append your signature key to the end of the value list.
        line_up_value += signature_key

        # Calculate the MD5 of the sorted value set.
        md5 = Digest::MD5.new
        md5.update(line_up_value)
        md5.hexdigest
      end

      # Convert ActiveMerchant::Billing::CreditCard.brand string into numeric code
      # for Credorax
      def card_brand_code(brand)

        map = {
          'visa'      => '1',
          'master'    => '2',
          'maestro'   => '9'
        } # All others map 0

        if map.has_key?(brand)
          return map[brand]
        else
          return '0' # Unknown
        end

      end
    end
  end
end
