require 'active_record'
require 'unix_crypt'
require 'bcrypt'

class CASino::ActiveRecordAuthenticator

  class AuthDatabase < ::ActiveRecord::Base
    self.abstract_class = true
  end

  # @param [Hash] options
  def initialize(options)
    @options = options

    eval <<-END
      class #{self.class.to_s}::#{@options[:table].classify} < AuthDatabase
        self.table_name = "#{@options[:table]}"
      end
    END

    @model = "#{self.class.to_s}::#{@options[:table].classify}".constantize
    @model.establish_connection @options[:connection]
  end

  def validate(username, password)
    ActiveRecord::Base.connection_handler.clear_active_connections!
    user = @model.send("find_by_#{@options[:username_column]}", username)
    user ||= @model.send("find_by_#{@options[:username_column_1]}", username)
    user ||= @model.send("find_by_#{@options[:username_column_2]}", username)
    user ||= @model.send("find_by_#{@options[:username_column_3]}!", username)
    password_from_database = user.send(@options[:password_column])

    if valid_password?(password, password_from_database)
      { username: user.send(@options[:username_column]),
        username_1: user.send(@options[:username_column_1]),
        username_2: user.send(@options[:username_column_2]),
        username_3: user.send(@options[:username_column_3]),
        extra_attributes: extra_attributes(user) }
    else
      false
    end

  rescue ActiveRecord::RecordNotFound
    false
  end

  def validate_after_confirm(username)
    ActiveRecord::Base.connection_handler.clear_active_connections!
    user = @model.send("find_by_#{@options[:username_column]}", username)
    user ||= @model.send("find_by_#{@options[:username_column_1]}", username)
    user ||= @model.send("find_by_#{@options[:username_column_2]}", username)
    user ||= @model.send("find_by_#{@options[:username_column_3]}!", username)

    if user
      { username: user.send(@options[:username_column]),
        username_1: user.send(@options[:username_column_1]),
        username_2: user.send(@options[:username_column_2]),
        username_3: user.send(@options[:username_column_3]),
        extra_attributes: extra_attributes(user) }
    else
      false
    end

  rescue ActiveRecord::RecordNotFound
    false
  end

  private
  def valid_password?(password, password_from_database)
    return false if password_from_database.blank?
    magic = password_from_database.split('$')[1]
    case magic
    when /\A2a?\z/
      valid_password_with_bcrypt?(password, password_from_database)
    else
      valid_password_with_unix_crypt?(password, password_from_database)
    end
  end

  def valid_password_with_bcrypt?(password, password_from_database)
    valid_password_with_bcrypt_without_pepper?(password, password_from_database) ||
      valid_password_with_bcrypt_with_pepper?(password, password_from_database)
  end

  def valid_password_with_bcrypt_with_pepper?(password, password_from_database)
    password_with_pepper = password + @options[:pepper].to_s
    BCrypt::Password.new(password_from_database) == password_with_pepper
  end

  def valid_password_with_bcrypt_without_pepper?(password, password_from_database)
    BCrypt::Password.new(password_from_database) == password
  end

  def valid_password_with_unix_crypt?(password, password_from_database)
    UnixCrypt.valid?(password, password_from_database)
  end

  def extra_attributes(user)
    attributes = {}
    extra_attributes_option.each do |attribute_name, database_column|
      attributes[attribute_name] = user.send(database_column)
    end
    attributes
  end

  def extra_attributes_option
    @options[:extra_attributes] || {}
  end
end
