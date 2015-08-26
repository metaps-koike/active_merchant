module ActiveMerchant #:nodoc:
  module Billing #:nodoc:

    #
    # == Description
    # The CredoraxGateway class supports interaction with {Credorax's}[http://www.credorax.com] {ePower Gateway API}[http://epower.credorax.com/home]ePower Gateway API.
    # This ActiveMerchant Gateway class supports two forms of interaction with Credorax.
    #
    # * Basic Operations - Credit Card must be supplied in Purchase and Authorisation calls, Previous referral code for other options
    # * Card-on-file Operations - Credit Card details are stored with Credorax and referenced in future operations with a Card Token
    #
    # This gateway class uses the following ActiveMerchant method to Credorax operation mapping
    # The standard list of gateway functions that most concrete gateway subclasses implement is:
    #
    # | ActiveMerchant  |  Basic                   |  Card-on-file
    # | --------------- | ------------------------ | --------------------------------
    # | purchase        |  [1] Sale                |  [11] Use Token - Sale
    # | authorize       |  [2] Authorisation       |  [12] Use Token - Auth
    # | capture         |  [3] Capture             |  [13] Use Token - Capture
    # | void            |  [4] Authorisation Void  |  [14] Token Auth Void
    # | refund          |  [7] Sale Void           |  [7] Sale Void
    # |                 |  [9] Capture Void        |  [9] Capture Void
    # |                 |  [5] Referral Credit     |  [5] Referral Credit
    # | store           |  N/A                     |  [10] Create Token
    #
    #
    class CredoraxGateway < Gateway

      ACTIONS = {
          sale:                         '1',
          authorisation:                '2',
          capture:                      '3',
          authorisation_void:           '4',
          referral_credit:              '5',
          sale_void:                    '7',
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
        missing_valid_3d_secure_data:           '-13',
        missing_card_secure_code:               '-12',
        currency_not_supported_by_merchant:     '-11',
        unclassified_error:                     '-10',
        parameter_malformed:                    '-9',
        package_signature_malformed:            '-8',
        no_response_from_gateway:               '-7',
        transaction_rejected:                   '-5',
        account_status_not_updated:             '-3',
        account_does_not_exist:                 '-2',
        account_already_exists:                 '-1',
        success:                                '0',
        transaction_denied:                     '1',
        transaction_denied_high_fraud_risk:     '2',
        transaction_denied_high_avs_risk:       '03',
        transaction_denied_interchange_timeout: '04',
        transaction_declined:                   '05',
        redirect_url_issued:                    '7',
        transaction_denied_luhn_check_fail:     '9',
        transaction_partially_approved:         '10',
        transaction_3d_enrolled:                '100'
      }

      C1_MIN_LENGTH = 5 # Billing Contact Name (c1) attribute minimum length

      self.test_url = 'https://intconsole.credorax.com/intenv/service/gateway'

      self.supported_countries = %w(US JP AT BE BG HR CY CZ DK EE FI FR DE GR HU IE IT LV LT LU MT NL PL PT RO SK SI ES SE GB) # US, JP, EU28
      self.default_currency = 'EUR'
      self.supported_cardtypes = [:visa, :master]

      # This class expects all amounts to be sent as cents (or equivalent, eg. US cents, EUR cents, GBP pence)
      # OR the actual amount when the currency does not have a sub-unit (eg. JP Yen)
      # So, it would expect $10.29 to be sent as 1029
      # and Y2104 as 2104
      self.money_format = :cents

      self.homepage_url = 'http://epower.credorax.com'
      self.display_name = 'Credorax'

      # Initialize the Gateway
      #
      # The gateway requires that valid data defined
      # in the +options+ hash.
      #
      # === Options
      #
      #  * <tt>:merchant_id => +string+</tt> - This will be assigned to you from Credorax. There is one per currency.
      #  * <tt>:md5_cipher_key => +string+</tt> - This will be assigned to you from Credorax and is used to generate parameter 'K' before sending API calls.
      #  * <tt>:name_on_statement => +string+</tt> Used to define the Billing Descriptor, by setting an 'DBA' (see "ePower Payment API - Implementation Guide Version 1.2 Apr 2013")
      #  * <tt>:live_url => +string+</tt> Credorax will only supply this to you after you have passed certification with them. (Only required if :test is false)
      #  * <tt>:test => +true+ or +false+</tt> - Force test transactions
      #  *
      #  * <tt>:cardholder_name_padding => +true+ or +false+</tt> - Pad the Billing Contact Name (c1) attribute if less than 5 characters in length. Defaults to TRUE
      #  * <tt>:cardholder_name_padding_character => +true+ or +false+</tt> - Specify the padding character for Billing Contact Name (c1) attribute, if enabled and required. Defaults to '-'
      #
      # For example:
      # ```
      # @gateway = CredoraxGateway.new(
      #     merchant_id: 'COMPX840',
      #     md5_cipher_key: 'A23SD5',
      #     name_on_statement: 'Company X'
      # )
      # ```
      #
      # # For example:
      # ```
      # @gateway = CredoraxGateway.new(
      #     merchant_id: 'COMPX840',
      #     md5_cipher_key: 'A23SD5',
      #     name_on_statement: 'Company X',
      #     cardholder_name_padding: true,
      #     cardholder_name_padding_character: '_'
      # )
      # ```
      #
      #
      def initialize(options={})
        requires!(options, :md5_cipher_key, :merchant_id, :name_on_statement)
        if options.has_key?(:test) && !options[:test].nil? && !options[:test]
          # Not test mode, also require the live_url
          requires!(options, :live_url)
        end

        unless options.has_key?(:cardholder_name_padding)
          options[:cardholder_name_padding] = true # Set default
        end

        unless options.has_key?(:cardholder_name_padding_character)
          options[:cardholder_name_padding_character] = '-' # Set default
        end

        super
      end

      # Perform a purchase.
      #
      # This method will either send a "[1] Sale" or "[11] Use Token - Sale" operation.
      # The method requires that valid data is defined in the +options+ hash.
      #
      # === money
      #
      # Two exponents are implied, without a decimal, except for currencies with zero exponents (e.g. JPY).
      # For example, when paying 10.00 GBP, the value should be sent as 1000. When paying 10 JPY, the value should be sent as 10.
      #
      # === Options
      #
      #  * <tt>:order_id    => +string+</tt> Unique id. Every call to this gateway MUST have a unique order_id, within the scope of a single merchant_id
      #  * <tt>:description => +string+</tt> The additional text that is shown on a cardholder's statement. Max length is 13 characters.
      #  * <tt>:merchant    => +string+</tt> This is used together with description. It is optional, and overides 'name_on_statement' configuration.
      #
      # Additional, the following is optional.
      #  * <tt>:ip => +string+</tt> - IP Address of Cardholder. It will default to '1.1.1.1' if not specified.
      #
      # ==== [1] Sale
      #
      # To use this operation, +payment+ should be a ActiveMerchant::Billing::CreditCard instance.
      # Specify the:
      #  * number
      #  * month
      #  * year
      #  * verification_value
      #  * name
      #
      # 'brand' will be ignored if it is specified.
      #
      # Cardholder billing address details can be stored in +options[:billing_address]+ or +options[:address]+
      #  * <tt>:city</tt> - The Cardholder's billing address city.
      #  * <tt>:state</tt> - State must be Subdivision Code (ISO-3166-2), max length 3 alphanumeric characters
      #  * <tt>:country</tt> - Country Code (ISO-3166)
      #  * <tt>:zip</tt> Billing Country PostCode
      #
      # Cardholder Email address MUST be specified in +options+
      #  * <tt>:email => +string+</tt> - Email address of the cardholder.
      #
      # ==== [11] Use Token - Sale
      #
      # To use this operation, +payment+ should be a +String+ representation of a Credorax 'token' that is defined in the 'g1' parameter.
      #
      # +options[:invoice]+ can be optionally specified, and should be used to store the Merchant Reference Number.
      #
      # Cardholder billing address details are not needed.
      #
      # === Response
      #
      # response[:authorization] contains a hash with the following key/value pairs
      #  * <tt>:token</tt> - This is not returned for [1] - Sale
      #  * <tt>:authorization_code</tt>
      #  * <tt>:response_id</tt>
      #  * <tt>:transaction_id</tt>
      #  * <tt>:previous_request_id</tt> - This is the same value as supplied in +options[:order_id]+
      #
      def purchase(money, payment, options={})

        if payment.is_a?(ActiveMerchant::Billing::CreditCard)

          requires!(options, :email, :order_id)
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
          requires!(options, :order_id)
          post = {
              'O' => ACTIONS[:use_token_sale],        # Operation Code
          }
          add_token(post, payment)
          add_request_id(post, options)
          add_invoice(post, money, options)           # Item information
          add_customer_data(post, options)
        end
        add_tracking(post, options)
        add_d2_certification(post, options)
        commit(post)
      end

      # Perform an authorization
      #
      # This method will either send a "[2] Authorise" or "[12] Use Token - Auth" operation.
      # The method requires that valid data is defined in the +options+ hash.
      #
      # === money
      #
      # Two exponents are implied, without a decimal, except for currencies with zero exponents (e.g. JPY).
      # For example, when paying 10.00 GBP, the value should be sent as 1000. When paying 10 JPY, the value should be sent as 10.
      #
      # === Options
      #
      #  * <tt>:order_id => +string+</tt> Unique id. Every call to this gateway MUST have a unique order_id, within the scope of a single merchant_id
      #
      # Additional, the following is optional.
      #  * <tt>:ip => +string+</tt> - IP Address of Cardholder. It will default to '1.1.1.1' if not specified.
      #
      # ==== [2] Authorise
      #
      # To use this operation, +payment+ should be a ActiveMerchant::Billing::CreditCard instance.
      # Specify the:
      #  * number
      #  * month
      #  * year
      #  * verification_value
      #  * name
      #
      # 'brand' will be ignored if it is specified.
      #
      #
      # Cardholder billing address details can be stored in +options[:billing_address]+ or +options[:address]+
      #  * <tt>:city</tt> - The Cardholder's billing address city.
      #  * <tt>:state</tt> - State must be Subdivision Code (ISO-3166-2), max length 3 alphanumeric characters
      #  * <tt>:country</tt> - Country Code (ISO-3166)
      #  * <tt>:zip</tt> Billing Country PostCode
      #
      # Cardholder Email address MUST be specified in +options+
      #  * <tt>:email => +string+</tt> - Email address of the cardholder.
      #
      # ==== [12] Use Token - Auth
      #
      # To use this operation, +payment+ should be a +String+ representation of a Credorax 'token' that is defined in the 'g1' parameter.
      #
      # +options[:invoice]+ can be optionally specified, and should be used to store the Merchant Reference Number.
      #
      # Cardholder billing address details are not needed.
      #
      # === Response
      #
      # response[:authorization] contains a hash with the following key/value pairs
      #  * <tt>:token</tt> - This is not returned for [2] - Authorisation
      #  * <tt>:authorization_code</tt>
      #  * <tt>:response_id</tt>
      #  * <tt>:transaction_id</tt>
      #  * <tt>:previous_request_id</tt> - This is the same value as supplied in +options[:order_id]+
      #
      def authorize(money, payment, options={})
        # Credit will be supplied in payment
        if payment.is_a?(ActiveMerchant::Billing::CreditCard)
          # Authorisation
          requires!(options, :email, :order_id)
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
          requires!(options, :order_id)
          post = {
              'O' => ACTIONS[:use_token_auth],     # Operation Code
          }
          add_request_id(post, options)
          add_token(post, payment)
          add_invoice(post, money, options)           # Item information
          add_customer_data(post, options)
          add_billing_address_data(post, options)     # Billing Address Info
        end
        add_tracking(post, options)
        add_d2_certification(post, options)
        commit(post)
      end

      # Perform a capture
      #
      # This method will either send a "[3] Authorise" or "[13] Use Token - Capture" operation.
      # The method requires that valid data is defined in the +options+ hash.
      #
      # === money
      #
      # Two exponents are implied, without a decimal, except for currencies with zero exponents (e.g. JPY).
      # For example, when paying 10.00 GBP, the value should be sent as 1000. When paying 10 JPY, the value should be sent as 10.
      # This can be respecified, and must a value that is equal to or less than the value specified in an authorization call.
      #
      # === Options
      #
      #  * <tt>:order_id => +string+</tt> Unique id. Every call to this gateway MUST have a unique order_id, within the scope of a single merchant_id
      #
      # Additional, the following is optional.
      #  * <tt>:ip => +string+</tt> - IP Address of Cardholder. It will default to '1.1.1.1' if not specified.
      #
      # ==== [3] Capture
      #
      # To use this operation, +authorization+ should NOT contain a populated +:token+ key/value pair.
      #
      # Cardholder billing address details are not needed.
      #
      # ==== [13] Use Token - Capture
      #
      # To use this operation, +authorization+ should contain a populated +:token+ key/value pair.
      # +options[:invoice]+ can be optionally specified, and should be used to store the Merchant Reference Number.
      #
      # Cardholder billing address details are not needed.
      #
      # === Response
      #
      # response[:authorization] contains a hash with the following key/value pairs
      #  * <tt>:token</tt> - This is not returned for [3] - Capture
      #  * <tt>:authorization_code</tt> - This will be set to 0
      #  * <tt>:response_id</tt>
      #  * <tt>:transaction_id</tt> - This will be set to nil
      #  * <tt>:previous_request_id</tt> - This is the same value as supplied in +options[:order_id]+
      #
      def capture(money, authorization, options={})

        if authorization.has_key?(:token) && !authorization[:token].blank?
          # Use Token - Capture
          requires!(options, :order_id)
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
          requires!(options, :order_id)
          post = {
              'O' => ACTIONS[:capture],               # Operation Code
          }
          add_request_id(post, options)
          add_customer_data(post, options)
          add_invoice(post, money, options)           # Item information - We allow partial amounts
          add_previous_request_data(post, authorization)
        end
        add_tracking(post, options)
        add_d2_certification(post, options)
        commit(post)
      end

      # Perform a refund of capture or sale.
      #
      # This method will either send a [7] Sale Void, [9] Capture Void, or [5] Referral Credit operation.
      # The method requires that valid data is defined in the +options+ hash.
      #
      # === money
      #
      # Partial Refund not supported
      #
      # === Options
      #
      #  * <tt>:order_id => +string+</tt> Unique id. Every call to this gateway MUST have a unique order_id, within the scope of a single merchant_id
      #
      # Additional, the following is optional.
      #  * <tt>:ip => +string+</tt> - IP Address of Cardholder. It will default to '1.1.1.1' if not specified.
      #
      # ==== [7] Sale Void, [9] Capture Void, [5] Referral Credit
      #
      # Cardholder billing address details are not needed.
      #
      # Also note, that due to Credorax's transaction states it is necessary to call the correct 'refund' operation
      # This requires the use of a non-standard +option+, with a key of +:refund_type+
      #  * <tt>:basic_post_clearing_credit  </tt> If the Sale/Capture time was before latest 'clearing date' (so, has now been passed clearing) (Basic Operation Cancel)
      #  * <tt>:capture                     </tt> If the transaction was created via [3] Capture AND was done so after the latest 'clearing' date (00:00UTC+01)
      #  * <tt>:sale                        </tt> If the transaction was created via [1] Sale AND was done so after the latest 'clearing' date (00:00UTC+01)
      #  * <tt>:post_clearing_credit        </tt> If the Sale/Capture time was before latest 'clearing date' (so, has now been passed clearing) (Token Operation Cancel)
      #
      # If this parameter is not specified, then it will default to :post_clearing_credit
      #
      # === Response
      #
      # response[:authorization] contains a hash with the following key/value pairs
      #  * <tt>:token</tt> - This is necessary when using +options[:refund_type]+ = +:post_clearing_credit+
      #  * <tt>:authorization_code</tt> - This will be set to 0
      #  * <tt>:response_id</tt>
      #  * <tt>:transaction_id</tt> - This will be set to nil
      #  * <tt>:previous_request_id</tt> - This is the same value as supplied in +options[:order_id]+
      #
      def refund(money, authorization, options={})
        requires!(options, :order_id, :refund_type)
        mapping = {
            basic_post_clearing_credit: ACTIONS[:referral_credit],
            capture:                    ACTIONS[:capture_void],
            sale:                       ACTIONS[:sale_void],
            post_clearing_credit:       ACTIONS[:token_referral_credit]
        }
        if options.has_key?(:refund_type) && !options[:refund_type].blank?
          opcode = mapping[options[:refund_type]]
        else
          opcode = ACTIONS[:token_referral_credit]
        end
        post = {
            'O' => opcode,              # Operation Code
        }
        if opcode == ACTIONS[:token_referral_credit]
          add_token(post, authorization[:token])
        end
        add_request_id(post, options)
        add_customer_data(post, options)
        add_previous_request_data(post, authorization)
        add_tracking(post, options)
        add_d2_certification(post, options)
        commit(post)
      end

      # Perform a void of an Authorisation
      #
      # This method will either send a "[4] Authorisation Void" or "[14] Token Auth Void" operation.
      # The method requires that valid data is defined in the +options+ hash.
      #
      # === money
      #
      # Only used by "[14] Token Auth Void", ignored by "[4] Authorisation Void"
      # Two exponents are implied, without a decimal, except for currencies with zero exponents (e.g. JPY).
      # For example, when paying 10.00 GBP, the value should be sent as 1000. When paying 10 JPY, the value should be sent as 10.
      #
      # === Options
      #
      #  * <tt>:order_id => +string+</tt> Unique id. Every call to this gateway MUST have a unique order_id, within the scope of a single merchant_id
      #
      # Additional, the following is optional.
      #  * <tt>:ip => +string+</tt> - IP Address of Cardholder. It will default to '1.1.1.1' if not specified.
      #
      # ==== [4] Authorisation Void
      #
      # To use this operation, +authorization+ should NOT contain a populated +:token+ key/value pair.
      #
      # Cardholder billing address details are not needed.
      #
      # ==== [14] Token Auth Void
      #
      # To use this operation, +authorization+ should contain a populated +:token+ key/value pair.
      #
      # Cardholder billing address details are not needed.
      #
      # === Response
      #
      # response[:authorization] contains a hash with the following key/value pairs
      #  * <tt>:token</tt> - This is not returned for [4] Authorisation Void
      #  * <tt>:authorization_code</tt> - This will be set to 0
      #  * <tt>:response_id</tt>
      #  * <tt>:transaction_id</tt> - This will be set to nil
      #  * <tt>:previous_request_id</tt> - This is the same value as supplied in +options[:order_id]+
      #
      def void(authorization, options={})

        if authorization.has_key?(:token) && !authorization[:token].blank?
          # Token Auth Void
          requires!(options, :order_id)
          post = {
              'O' => ACTIONS[:token_auth_void],       # Operation Code
          }
          add_token(post, authorization[:token])
          add_request_id(post, options)
          add_customer_data(post, options)
          add_previous_request_data(post, authorization)
        else
          # Authorisation Void
          requires!(options, :order_id)
          post = {
              'O' => ACTIONS[:authorisation_void],    # Operation Code
          }
          add_request_id(post, options)
          add_customer_data(post, options)
          add_previous_request_data(post, authorization)
        end
        add_tracking(post, options)
        add_d2_certification(post, options)
        commit(post)
      end

      # Store a Credit Card and obtain a token that will be used to represent it
      #
      # This method will either send a "[3] Authorise" or "[13] Use Token - Capture" operation.
      # The method requires that valid data is defined in the +options+ hash.
      #
      # === Options
      #
      #  * <tt>:order_id => +string+</tt> Unique id. Every call to this gateway MUST have a unique order_id, within the scope of a single merchant_id
      #  * <tt>:email => +string+</tt> - Email address of the cardholder.
      #
      # Additional, the following is optional.
      #  * <tt>:ip => +string+</tt> - IP Address of Cardholder. It will default to '1.1.1.1' if not specified.
      #
      #  +payment+ is a ActiveMerchant::Billing::CreditCard instance.
      # Specify the:
      #  * number
      #  * month
      #  * year
      #  * verification_value
      #  * name
      #
      # 'brand' will be ignored if it is specified.
      #
      # Cardholder billing address details can be stored in +options[:billing_address]+ or +options[:address]+
      #  * <tt>:city</tt> - The Cardholder's billing address city.
      #  * <tt>:state</tt> - State must be Subdivision Code (ISO-3166-2), max length 3 alphanumeric characters
      #  * <tt>:country</tt> - Country Code (ISO-3166)
      #  * <tt>:zip</tt> Billing Country PostCode
      #
      #
      # === Response
      #
      # response[:authorization] contains a hash with the following key/value pairs
      #  * <tt>:token</tt>
      #  * <tt>:authorization_code</tt>
      #  * <tt>:response_id</tt>
      #  * <tt>:transaction_id</tt>
      #  * <tt>:previous_request_id</tt> - This is the same value as supplied in +options[:order_id]+
      #
      def store(payment, options = {})

        if payment.is_a?(ActiveMerchant::Billing::CreditCard)
          requires!(options, :order_id, :email)
          post = {
              'O' => ACTIONS[:create_token],       # Operation Code
          }
          add_request_id(post, options)
          # Future release of Credorax API will use options[:store_verification_amount] in call to add_invoice
          add_invoice(post, 1, options) # Hard coded amount value, as it gets ignore by Credorax (it always returns a4=5 (500) in response for example)
          add_payment(post, payment)
          add_customer_data(post, options)
          add_billing_address_data(post, options)
        else
          raise ArgumentError, 'payment must be a Credit card (ActiveMerchant::Billing::CreditCard)'
        end
        add_d2_certification(post, options)
        add_tracking(post, options)
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

        if options[:ip].present?
          post['d1'] = options[:ip]                 # User's IP
        else
          post['d1'] = '1.1.1.1'
        end
      end

      def add_billing_address_data(data, options)
        billing_address = options[:billing_address] || options[:address]
        if billing_address
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

        if options.has_key?(:currency) && !options[:currency].nil?
          # Override the default currency
          post['a5'] = options[:currency]
        end

        if options.has_key? :description
          if options[:description].length > 13
            raise ArgumentError, 'transaction description has maximum length of 13 characters'
          end
          dba_text = @options[:name_on_statement] # Gateway Scoped 'DBA' text
          if options[:merchant].present?
            raise(ArgumentError, 'transaction merchant has maximum length of 25 characters') if options[:merchant].length > 25
            dba_text = options[:merchant] # Transaction Scoped 'DBA' text
          end
          post['i2'] = "#{dba_text}*#{options[:description]}" # Transaction Description
        end

      end

      def add_tracking(post, options)
        if options.has_key? :invoice
          post['h9'] = options[:invoice] # Merchant Reference Number
        end
      end

      def add_payment(post, payment)

        unless payment.brand.blank?
          # Specifying the brand is not recommended, but must support it
          # Need to by-pass the getter method on ActiveMerchant::Billing::CreditCard which does a
          # BIN to Brand lookup
          post['b2'] = card_brand(payment.instance_variable_get('@brand'))
        end

        payment_name = clean_cardholder_name(payment.name)

        raise(ArgumentError, 'billing contact name must be at least than 5 characters') unless c1_field_data_valid?(payment_name)
        raise(ArgumentError, 'cvv can only be 3 characters') unless payment.verification_value.length == 3

        post['b1'] = payment.number                 # Card Number
        post['b3'] = '%02d' % payment.month         # Card Expiration Month (MM) - ActiveMerchant Card stores as FixNum
        post['b4'] = payment.year.to_s[-2..-1]      # Card Expiration Year (YY) - ActiveMerchant Card stores as FixNum
        post['b5'] = payment.verification_value     # Card Secure Code, Visa
        post['c1'] = pad_c1_field(payment_name)     # Billing Contact Name
      end

      def clean_cardholder_name(payment_name)
        # If a single word/name is supplied to ActiveMerchant::Billing::CreditCard,
        # the name method is prefixing a space.
        # It's returning "#{firstname} #{lastname}" where firstname is nil, and lastname is the single name
        # This method strips any leading space characters, BUT ONLY IF we are enabling padding
        return payment_name unless (@options[:cardholder_name_padding] == true)
        payment_name.strip
      end

      def c1_field_data_valid?(payment_name)
        (@options[:cardholder_name_padding] == true) || (payment_name.length >= C1_MIN_LENGTH)
      end

      def pad_c1_field(payment_name)
        return payment_name unless (@options[:cardholder_name_padding] == true)
        payment_name.ljust(C1_MIN_LENGTH, @options[:cardholder_name_padding_character])
      end

      def parse(body)
        results = {}
        body.split(/&/).each do |pair|
          key,val = pair.split(/=/)
          results[key] = val
        end
        results
      end

      def add_d2_certification(post, options)
        # This is only used during certification purposes, and is ignored in integration environments
        # However, it should not normally be specified.
        if options.has_key? :d2
          post['d2'] = options[:d2]
        end
      end

      def commit(parameters)

        url = (test? ? test_url : @options[:live_url])

        # Add Merchant ID,
        parameters['M'] = @options[:merchant_id]    # MerchantID
        # then create the MD5 message and add to parameters
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
        message = response['z3']
        unless success_from(response)
          codes = []
          codes << response['z2']
          codes << response['z6'] unless response['z6'].nil?
          message += " (%s)" % codes.join(',')
        end
        message
      end

      def authorization_from(response)
        auth = {
          authorization_code: response['z4'],
          response_id: response['z1'],
          transaction_id: response['z13'],
          previous_request_id: response['a1'],
          response_reason_code: response['z6']
        }
        unless response['g1'].blank?
          auth[:token] = response['g1']
        end
        unless response['d2'].blank?
          auth[:d2] = response['d2']
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

      def card_brand(brand)
        if brand.is_a? Symbol
          branding_mapping = {
              visa:     1,
              master:   2,
              maestro:  9
          }
          return branding_mapping.has_key?(brand) ? branding_mapping[brand] : 0
        end
        # use value supplied
        return brand.to_s
      end

    end
  end
end
