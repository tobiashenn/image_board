require 'sinatra'
require 'data_mapper'
require 'haml'
require 'bcrypt'
require 'date'
require 'sinatra/flash'
require 'carrierwave/datamapper'
require "will_paginate-bootstrap"
require 'will_paginate/data_mapper'
require 'sanitize'
require 'json'
require 'ValidateEmail'
require 'rinku'
require 'yaml'

# CONFIGURATION
set :server, :puma
set :markdown, :layout_engine => :haml, :layout => :layout
set :haml, :format => :html5
WillPaginate.per_page = 10
secrets_yaml = YAML.load_file('config/config.yml')

CarrierWave.configure do |config|
  amazon_S3_config = YAML.load_file('config/fog_amazon_S3.yml')
  config.fog_credentials = amazon_S3_config.inject({}){|memo,(k,v)| memo[k.to_sym] = v; memo}
  config.fog_directory  = 'ibs3bucket'
  config.fog_public     = true
end

configure :ocean do
  set :environment, :production
  set :port, 9977
  set :bind, '0.0.0.0'
end

# STARTUP PROCEDURES
puts "Engine started with Ruby Version #{RUBY_VERSION}-p#{RUBY_PATCHLEVEL}"
signup_hash = secrets_yaml['hash']
CarrierWave.clean_cached_files!

use Rack::Session::Cookie, :secret => secrets_yaml['cookie_secret']
DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/image_board.db")

# MODELS
class ImageUploader < CarrierWave::Uploader::Base
  include CarrierWave::MiniMagick
  storage :fog
    
  version :deliver do
    process resize_to_limit: [800, 10000]
  end
    
  def md5
    uploaded_file = model.send(mounted_as)
    @md5 ||= Digest::MD5.hexdigest(uploaded_file.read)
  end
    
  def filename
       "#{secure_token}.#{file.extension}" if original_filename.present?
  end

  protected
  def secure_token
    var = :"@#{mounted_as}_secure_token"
    model.instance_variable_get(var) or model.instance_variable_set(var, SecureRandom.uuid)
  end  
end

class User
  include DataMapper::Resource
  property :id, Serial
  property :privilege_lvl, Integer, :default  => 0 
  property :name, String, :unique => true
  property :password_hash, BCryptHash
  property :email, String, :required => true, :unique => true, :format => :email_address, :default => "mail@host.com"
  has n, :images
  has n, :comments
  has n, :favs
end

class Image
  include DataMapper::Resource
  property :id, Serial
  mount_uploader :file, ImageUploader
  belongs_to :user
  property :posted_at, DateTime
  has n, :comments
  has n, :favs
end

class Comment
  include DataMapper::Resource
  property :id, Serial
  property :posted_at, DateTime
  property :text, String, :length => 1024
  belongs_to :image
  belongs_to :user
end

class Fav
  include DataMapper::Resource
  property :id, Serial
  belongs_to :image
  belongs_to :user
end

# DATABASE MIGRATIONS
DataMapper.finalize.auto_upgrade!

# HELPERS
helpers do
  def login?
    if session[:username].nil?
      return false
    else
      return true
    end
  end
  
  def pluralize(n, singular, plural=nil)
      if n == 1
          "#{singular}"
      elsif plural
          "#{plural}"
      else
          "#{singular}s"
      end
  end
  
  def valid_ext?(ext)
    %w(.jpg .jpeg .gif .png).include?(ext)
  end
  
  def admin?
    user = User.first(:name => session[:username])
    user.privilege_lvl == 99
  end
  
  def has_faved_image?(image)
    user = User.first(:name => session[:username])
    if Fav.all(:user => user, :image => image).count > 0 
      return true
    else
      return false
    end
  end
  
  def is_own_image?(image)
    session[:username] == image.user.name
  end
  
  def favs_received(user)
    user.images.reduce(0){|favs, image| favs + image.favs.count}
  end
end

# ROUTES
get '/' do
  if login?
    redirect '/images'
  end
  haml :index
end

post'/comments/:id' do
  if login?
    image = Image.first(:id => params[:id])
    user = User.first(:name => session[:username])
    comment = Rinku.auto_link(Sanitize.clean(params['comment']), mode=:all, link_attr=nil, skip_tags=nil)
    Comment.create(:image => image, :user => user, :text => comment, :posted_at => Time.now)
  end
  redirect back
end

get '/current_user_profile' do
  if login?
    user = User.first(:name => session[:username])
    redirect "/users/#{user.id}"
  end
  redirect '/'
end

post '/delete_image/:id' do
  if (login? and admin?)
    if (image = Image.first(:id => params[:id]))
      image.comments.each do |comment|
        comment.destroy!
      end
      image.remove_file!
      image.destroy!
    end
  flash[:error] = "Image deleted!"
  end
  redirect '/'
end

get '/destroy' do
  if (login? and admin?)
    haml :destroy
  else
    redirect '/'
  end
end

post '/destroy' do
  if (login? and admin?)
    Image.all.each do |image|
      image.destroy!
    end    
    DataMapper.auto_migrate!
    CarrierWave.clean_cached_files!
    flash[:error] = "Database reset!"
  end
  redirect '/logout'
end

post '/fav_image/:id' do
  if login?
    image = Image.first(:id => params[:id])
    if not ( has_faved_image?(image) or is_own_image?(image) )
      user = User.first(:name => session[:username])
      Fav.create(:image => image, :user => user)
    end
  end
  redirect back
end

get '/images' do 
  if login?
    @images = Image.paginate(:page => params[:page],:order => [ :posted_at.desc ])
    haml :images
  else
    redirect '/'
  end
end

get '/images/:id' do
  if login?
    @image = Image.first(:id => params[:id])
    @fav_list = Fav.all(:image => @image)
    haml :image_details
  else
    redirect '/'
  end
end

post '/login' do
  @user = User.first(:name => params[:username])
  if @user
    if BCrypt::Password.new(@user[:password_hash]) == params[:password]
      session[:username] = params[:username]
      redirect '/images'
    end
  end
  flash[:error] = "Wrong user name or password!"
  redirect '/'
end

get '/logout' do
  session[:username] = nil
  redirect '/'
end

get '/recreate_versions' do
  if (login? and admin?)
    Image.all.each do |image|
      puts image.file.recreate_versions!
    end
  end
  redirect '/'
end

get '/signup' do
  haml :signup
end

post '/signup' do
  if not User.first(:name => params[:username])
    if not ValidateEmail.validate(params[:email], true)
      flash[:error] = "No valid email address given!"
      redirect back
    end
    if BCrypt::Password.new(signup_hash) == params[:signupcode]   
      password_hash = BCrypt::Password.create(params[:password])  
      User.create(:name => params[:username], :password_hash => password_hash, :email => params[:email])
      session[:username] = params[:username]
      flash[:message] = "Signed up!"
      redirect '/'
    end
  end
  flash[:error] = "User name not available or wrong sign-up code!"
  redirect back
end

get '/upload' do
  if login?
    haml :upload
  else
    redirect '/'
  end
end
 
post '/upload' do 
  if login?
    user = User.first(:name => session[:username])
    if not valid_ext?( File.extname(params['myfile'][:filename]).downcase )
      flash[:error] = "Wrong file type - not uploaded!"
      redirect '/images'
    end
    Image.create(:user => user, :file => params['myfile'], :posted_at => Time.now)
  end
  redirect '/images'
end

get '/users' do
  if login?
    @users = User.all
    haml :user_list
  else
    redirect '/'
  end
end

get '/users/:id' do
  if login?
    @user = User.first(:id => params[:id])
    @images = @user.images.paginate(:page => params[:page],:order => [ :posted_at.desc ])
    haml :user_profile
  else
    redirect '/'
  end
end