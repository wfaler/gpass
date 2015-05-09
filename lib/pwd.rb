require 'json'
require 'gpgme'
require 'securerandom'
require 'csv'

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
  @@crypto = nil
  @@passphrase = nil
  
  def init
    if File.exist?(storeDir + '/index.gpg') then
      raise ArgumentError, storeDir + "/index.gpg already exists!", caller
    end    
    passphrase = get_password()
    confirm_passphrase = get_password("\nConfirm Passphrase: ")
    if passphrase == confirm_passphrase then
      @@passphrase = passphrase
      
      Dir.mkdir(storeDir) unless File.exist?(storeDir)
      
      Dir.mkdir(storeDir + '/secrets') unless File.exist?(storeDir + '/secrets')
      write_index({})
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
    _new(key,ARGV[2].to_i, ARGV[3])
  end
  
  def _new(key,len, username)
    pwd = gen_pwd(len)
    entry = {:password => pwd}
    unless username.nil? then
      entry[:username] = username
    end
    new_entry(key, entry)
    puts 'generated password: ' + pwd
  end
  
  def show
    key = ARGV[1]
    _show(key)
  end
  
  def _show(key)
    hash = get_entry(key)
    hash.keys.sort.each do |key|
      puts "#{key}: " + hash[key]
    end
  end
  
  def new_entry(key, entry)
    file = pwdDir + SecureRandom::uuid() + '.gpg'
    index = get_index()
    
    if File.exists?(file) then
      raise ArgumentError, "Duplicate file name generated!", caller
    end
    
    unless index.has_key?(key) then  
      index[key] = file
      write_hash_to_file(entry,file)
      write_index(index)
    else
      raise ArgumentError,'entry for ' + key + ' already exists, use "update" to edit an existing entry',caller
    end
  end
  
  def add
    key = ARGV[1]
    add_key = ARGV[2]
    add_value = ARGV[3]
    
    addOrUpdate(key,add_key,add_value,false)
  end
  
  def addOrUpdate(key,add_key,add_value,isUpdate)
    hash = get_entry(key)
    if isUpdate then
      puts 'do you really want to update? (y/n)'
      yes_or_no =  STDIN.gets.chomp
      if yes_or_no == 'y' then
        hash[add_key] = add_value
        write_hash_to_file(hash,get_entry_file(key))
        puts 'value updated'
      else
        puts 'update cancelled'
      end
    else
      unless hash.has_key?(add_key) then
        hash[add_key] = add_value
        write_hash_to_file(hash,get_entry_file(key))
      else
        raise ArgumentError,'entry for ' + add_key + ' already exists, use "update" to edit an existing entry',caller
      end
    end
  end
  
  def search
    index = get_index()
    i = 0
    puts 'Matching entries: '
    titles = []
    index.keys.sort.each do |key|
      if ARGV[1].nil? then
        puts i.to_s + '.' + key
        titles.push(key)
        i = i + 1
      elsif key.downcase.include? ARGV[1].downcase
        puts i.to_s + '.' + key
        titles.push(key)
        i = i + 1
      end
    end
    puts 'enter the number of the entry you want'
    selection = STDIN.gets.chomp.to_i
    puts 'show,pass or clipboard? (s/p/c)'
    mode = STDIN.gets.chomp
    key = titles[selection]
    if mode == 's' then
      _show(titles[selection])
    elsif mode == 'p' then
      _pass(key)
    elsif mode == 'c' then
      _clip(key)
    end

    # search and select
  end
  
  # alias for search
  def list
    search
  end
  
  def update
    key = ARGV[1]
    add_key = ARGV[2]
    add_value = ARGV[3]
    
    addOrUpdate(key,add_key,add_value,true)
  end

  def rm
    # remove entry
  end

  def rm_keys
    # remove keys for entry
  end

  def reencrypt
    # re-encrypt stuff based on settings, change of passphrase or whatever
  end

  def import1password
    csv = CSV.read(ARGV[1], headers:true)
    headers = csv.headers()
    titles = []
    
    csv.each do |row|
      entry = {}
      headers.each do |header|
        unless row.field(header).nil? then
          entry[header.downcase] = row.field(header)
        end
      end
      i = 1
      while titles.include?(entry['title']) do
        entry['title'] = entry['title'] + '-' + i.to_s
        i = i + 1
      end
      new_entry(entry['title'],entry)
      titles.push(entry['title'])
    end
  end

  def clip
    key = ARGV[1]
    _clip(key)
  end

  def _clip(key)
    hash = get_entry(key)
    pass = hash['password']
    `echo '#{pass}' | pbcopy`
    puts 'password in clipboard, will be removed in 45 seconds..'
    sleep 45
    `echo '' | pbcopy`
  end

  def pass
    key = ARGV[1]
    _pass(key)
  end


  def generate
    gen_pwd(ARGV[1].to_i)
  end

  def _pass(key)
    hash = get_entry(key)
    puts 'password: ' + hash['password']
  end


  def get_entry(key)
    get_hash_from_file(get_entry_file(key))
  end

  def get_entry_file(key)
    get_index()[key]
  end

  def reconcile
    index = get_index()
    values = []
    index.keys.sort.each do |key|
      values.push(index[key])
    end
    Dir[pwdDir + "*.gpg"].each do |file|
      unless values.include? file.to_s then
        puts file.to_s
      end
    end
  end


  def pass_function(pass, uid_hint, passphrase_info, prev_was_bad, fd)    
    if @@passphrase.nil? then
      @@passphrase = get_password()
    end
    io = IO.for_fd(fd, 'w')
    io.puts @@passphrase
    io.flush
    io.close
  end

  def write_hash_to_file(hash, file_name)
    json_string = hash.to_json
    if @@crypto.nil? then
      @@crypto = GPGME::Crypto.new(armor: false,symmetric: true, passphrase_callback: method(:pass_function))
    end

    encrypted = @@crypto.encrypt(json_string)
    write_to_file(file_name,encrypted)
  end

  def write_to_file(file_name, contents)
    begin
      file = File.open(file_name, "w")
      file.write(contents) 
    rescue IOError => e
    #some error occur, dir not writable etc.
    ensure
      file.close unless file == nil
    end
  end

  def get_hash_from_file(file_name)
    contents = read_file(file_name)
    if @@crypto.nil? then
      @@crypto = GPGME::Crypto.new(armor: false, symmetric: true, passphrase_callback: method(:pass_function))      
    end

    decrypted = @@crypto.decrypt contents
    JSON.parse(decrypted.to_s)
  end

  def read_file(file_name)
    file = File.open(file_name)
    contents = ""
    file.each {|line|
      contents << line
    }
    file.close
    contents
  end


  def get_index()
    get_hash_from_file(storeDir + "/index.gpg")
  end
  
  def get_password(prompt="Passphrase: ")
    result = `read -s -p "#{prompt}" password; echo $password`.chomp
    @@passphrase = result
    puts ''
    result
  end

  def storeDir
    if ENV['pwd_dir'].nil? then
      Dir.home() + '/.pwdapp'
    else
      ENV['pwd_dir']
    end
  end
  
  def pwdDir
    storeDir + '/secrets/'
  end

  def write_index(index)
    write_hash_to_file(index, storeDir + '/index.gpg')
  end
  
  def gen_pwd(len)
    o = [('a'..'z'), ('A'..'Z'),(0..9)].map { |i| i.to_a }.flatten + ['-','_']
    (0...len).map { o[rand(o.length)] }.join
  end

end


include Pwd
fn_name = ARGV[0]
Pwd::method(fn_name).call()
