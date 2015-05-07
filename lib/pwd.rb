require 'json'
require 'gpgme'
require 'securerandom'


module OS
  def OS.windows?
    (/cygwin|mswin|mingw|bccwin|wince|emx/ =~ RUBY_PLATFORM) != nil
  end

  def OS.mac?
   (/darwin/ =~ RUBY_PLATFORM) != nil
  end

  def OS.unix?
    !OS.windows?
  end

  def OS.linux?
    OS.unix? and not OS.mac?
  end
end

module Pwd

  def init
    if File.exist?(storeDir + '/index.gpg') then
      raise ArgumentError, storeDir + "/index.gpg already exists!", caller
    end    
    passphrase = get_password()
    confirm_passphrase = get_password("\nConfirm Passphrase: ")
    if passphrase == confirm_passphrase then
      Dir.mkdir(storeDir) unless File.exist?(storeDir)
      Dir.mkdir(storeDir + '/secrets') unless File.exist?(storeDir + '/secrets')
      write_index({},passphrase)
      puts 'initialised secrets repo in ~/.pwdapp'
    else
      raise ArgumentError, 'passphrases do not match!',caller
    end
  end

  def new
    key = ARGV[1]
    if ARGV[2].to_i < 5 then
      raise ArgumentError, "must provide a length argument for password to generate", caller
    end
    new_(key,ARGV[2].to_i, ARGV[3])
  end

  def new_(key,len, username)
    passphrase = get_password()
    pwd = gen_pwd(len)
    file = pwdDir + SecureRandom::uuid() + '.gpg'
    index = get_index(passphrase)

    if File.exists?(file) then
      raise ArgumentError, "Duplicate file name generated!", caller
    end
    
    unless index.has_key?(key) then
      entry = {:password => pwd}
      unless username.nil? then
        entry[:username] = username
      end
      index[key] = file
      write_hash_to_file(entry,passphrase,file)
      write_index(index, passphrase)
      puts 'generated password: ' + pwd
    else
      raise ArgumentError,'entry for ' + key + ' already exists, use "update" to edit an existing entry',caller
    end
  end

  def show
    passphrase = get_password()
    key = ARGV[1]
    show_(passphrase,key)
  end

  def show_(passphrase, key)
    hash = get_entry(passphrase, key)
    hash.keys.sort.each do |key|
      puts "#{key}: " + hash[key]
    end
  end

  def add
    passphrase = get_password()
    key = ARGV[1]
    add_key = ARGV[2]
    add_value = ARGV[3]
    
    addOrUpdate(passphrase,key,add_key,add_value,false)
  end

  def addOrUpdate(passphrase,key,add_key,add_value,isUpdate)
    hash = get_entry(passphrase,key)
    if isUpdate then
      puts 'do you really want to update? (y/n)'
      yes_or_no =  STDIN.gets.chomp
      if yes_or_no == 'y' then
        hash[add_key] = add_value
        write_hash_to_file(hash,passphrase,get_entry_file(passphrase, key))
        puts 'value updated'
      else
        puts 'update cancelled'
      end
    else
      unless hash.has_key?(add_key) then
        hash[add_key] = add_value
        write_hash_to_file(hash,passphrase,get_entry_file(passphrase, key))
      else
        raise ArgumentError,'entry for ' + add_key + ' already exists, use "update" to edit an existing entry',caller
      end
    end
  end

  def search
    passphrase = get_password()
    index = get_index(passphrase)
    i = 0
    puts 'Matching entries: '
    index.keys.sort.each do |key|
      if ARGV[1].nil? then
        puts i.to_s + '.' + key
        i = i + 1
      elsif key.downcase.include? ARGV[1].downcase
        puts i.to_s + '.' + key
        i = i + 1
      end
    end
    puts 'enter the number of the entry you want'
    selection = STDIN.gets.chomp.to_i
    puts 'show,pass or clipboard? (s/p/c)'
    mode = STDIN.gets.chomp
    key = index.keys.sort[selection]
    if mode == 's' then
      show_(passphrase,index.keys.sort[selection])
    elsif mode == 'p' then
      pass_(passphrase,key)
    elsif mode == 'c' then
      clip_(passphrase,key)
    end

    # search and select
  end

  # alias for search
  def list
    search
  end

  def update
    passphrase = get_password()
    key = ARGV[1]
    add_key = ARGV[2]
    add_value = ARGV[3]
    
    addOrUpdate(passphrase,key,add_key,add_value,true)
  end

  def rm
    # remove entry
  end

  def import1password
    
  end

  def clip
    passphrase = get_password()
    key = ARGV[1]
    clip_(passphrase, key)
  end

  def clip_(passphrase,key)
    hash = get_entry(passphrase,key)
    pass = hash['password']
    `echo '#{pass}' | pbcopy`
    puts 'password in clipboard, will be removed in 45 seconds..'
    sleep 45
    `echo '' | pbcopy`
  end

  def pass
    passphrase = get_password()
    key = ARGV[1]
    pass_(passphrase,key)
  end

  def pass_(passphrase, key)
    hash = get_entry(passphrase,key)
    puts 'password: ' + hash['password']
  end

  def generate
    gen_pwd(ARGV[1].to_i)
  end

  def get_entry(passphrase, key)
    get_hash_from_file(passphrase,get_entry_file(passphrase,key))
  end

  def get_entry_file(passphrase, key)
    get_index(passphrase)[key]
  end

  def write_hash_to_file(hash, passphrase, file_name)
    json_string = hash.to_json
    crypto = GPGME::Crypto.new :password => passphrase
    encrypted = crypto.encrypt json_string, :symmetric => true
    begin
      file = File.open(file_name, "w")
      file.write(encrypted) 
    rescue IOError => e
    #some error occur, dir not writable etc.
    ensure
      file.close unless file == nil
    end
  end

  def get_hash_from_file(passphrase, file_name)
    crypto = GPGME::Crypto.new :password => passphrase
    file = File.open(file_name)
    contents = ""
    file.each {|line|
      contents << line
    }
    decrypted = crypto.decrypt contents, :symmetric => true
    JSON.parse(decrypted.to_s)
  end


  def get_index(passphrase)
    get_hash_from_file(passphrase,storeDir + "/index.gpg")
  end
  
  def get_password(prompt="Passphrase: ")
    result = `read -s -p "#{prompt}" password; echo $password`.chomp
    puts ''
    result
  end

  def storeDir
    Dir.home() + '/.pwdapp'
  end
  
  def pwdDir
    storeDir + '/secrets/'
  end

  def write_index(index, passphrase)
    write_hash_to_file(index,passphrase, storeDir + '/index.gpg')
  end
  
  def gen_pwd(len)
    o = [('a'..'z'), ('A'..'Z'),(0..9)].map { |i| i.to_a }.flatten + ['-','_']
    (0...len).map { o[rand(o.length)] }.join
  end

end


include Pwd
fn_name = ARGV[0]
Pwd::method(fn_name).call()
