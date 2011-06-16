class Mail
  attr_reader :page, :config, :data, :errors
  # config can have some separate parts
  def initialize(page, config, data)
    @page, @config, @data = page, config.with_indifferent_access, data
    @required = @data.delete(:required)
    @errors = {}
  end

  def self.valid_config?(config)
    return false if config.blank?
    config.keys.each do |key|
      return false if config[key]['recipients'].blank? and config[key]['recipients_field'].blank?
      return false if config[key]['from'].blank? and config[key]['from_field'].blank?
    end
    true
  end

  def valid?(config_key)
    unless defined?(@valid)
      @valid = true
      if recipients(config_key).blank? and !is_required_field?(config[config_key][:recipients_field])
        errors['form'] = 'Recipients are required.'
        @valid = false
      end

      if recipients(config_key).any?{|e| !valid_email?(e)}
        errors['form'] = 'Recipients are invalid.'
        @valid = false
      end

      if from(config_key).blank? and !is_required_field?(config[config_key][:from_field])
        errors['form'] = 'From is required.'
        @valid = false
      end

      if !valid_email?(from(config_key))
        errors['form'] = 'From is invalid.'
        @valid = false
      end

      if @required
        @required.each do |name, msg|
          if data[name].blank?
            errors[name] = ((msg.blank? || %w(1 true required).include?(msg)) ? "is required." : msg)
            @valid = false
          end
        end
      end
    end
    @valid
  end

  def from(config_key)
    config[config_key][:from] || data[config[config_key][:from_field]]
  end

  def recipients(config_key)
    config[config_key][:recipients] || data[config[config_key][:recipients_field]].split(/,/).collect{|e| e.strip}
  end

  def reply_to(config_key)
    config[config_key][:reply_to] || data[config[config_key][:reply_to_field]]
  end

  def sender(config_key)
    config[config_key][:sender]
  end

  def subject(config_key)
    data[:subject] || config[config_key][:subject] || "Form Mail from #{page.request.host}"
  end
  
  def cc(config_key)
    data[config[config_key][:cc_field]] || config[config_key][:cc] || ""
  end
  
  def send
    config.keys.each do |config_key|
      return false if not valid? config_key

      part_name = "email_#{config_key}".to_sym
      plain_body = (page.part( part_name ) ? page.render_part( part_name ) : page.render_part( :email_plain ))
      html_body = page.render_part( "#{part_name.to_s}_html".to_sym ) || nil

      if plain_body.blank? and html_body.blank?
        plain_body = <<-EMAIL
  The following information was posted:
  #{data.to_hash.to_yaml}
        EMAIL
      end

      headers = { 'Reply-To' => reply_to(config_key) || from(config_key) }
      if sender(config_key)
        headers['Return-Path'] = sender(config_key)
        headers['Sender'] = sender(config_key)
      end

      Mailer.deliver_generic_mail(
        :recipients => recipients(config_key),
        :from => from(config_key),
        :subject => subject(config_key),
        :plain_body => plain_body,
        :html_body => html_body,
        :cc => cc(config_key),
        :headers => headers
      )
      @sent = true
    end
  rescue Exception => e
    errors['base'] = e.message
    @sent = false
  end

  def sent?
    @sent
  end

  protected

  def valid_email?(email)
    (email.blank? ? true : email =~ /.@.+\../)
  end
  
  def is_required_field?(field_name)
    @required && @required.any? {|name,_| name == field_name}
  end
end
