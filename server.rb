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
require 'open-uri'
require 'exifr'
require 'securerandom'

# CONFIGURATION
set :server, :puma
set :markdown, :layout_engine => :haml, :layout => :layout
set :haml, :format => :html5
WillPaginate.per_page = 10
config_yaml = YAML.load_file('config/config.yml')

CarrierWave.configure do |config|
  amazon_S3_config = YAML.load_file('config/fog_amazon_S3.yml')
  config.fog_credentials = amazon_S3_config.inject({}){|result, (k,v)| result[k.to_sym] = v; result}
  config.fog_directory  = config_yaml['S3bucket']
end

configure :ocean do
  set :environment, :production
  set :port, 9977
  set :bind, '0.0.0.0'
end

# STARTUP PROCEDURES
puts "Engine started with Ruby Version #{RUBY_VERSION}-p#{RUBY_PATCHLEVEL}"
CarrierWave.clean_cached_files!
use Rack::Session::Cookie, :secret => SecureRandom.hex(64)
DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/image_board.db")

# MODELS
class ImageUploader < CarrierWave::Uploader::Base
  include CarrierWave::MiniMagick
  storage :fog
    
  version :deliver do
    process resize_to_limit: [800, 10000]
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
  property :email, String, :required => true, :unique => true, :format => :email_address
  has n, :images
  has n, :comments
  has n, :favs
end

class Image
  include DataMapper::Resource
  mount_uploader :file, ImageUploader
  property :id, Serial
  property :posted_at, DateTime
  property :exif_model, String
  property :exif_focallength, String
  property :exif_aperture, String
  property :exif_shutterspeed, String
  property :exif_iso, String
  belongs_to :user
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
    return true unless session[:username].nil?
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
    User.first(:name => session[:username]).privilege_lvl == 99
  end
  
  def has_faved_image?(image)
    return true if Fav.all(:user => User.first(:name => session[:username]), :image => image).count > 0
  end
  
  def is_own_image?(image)
    session[:username] == image.user.name
  end
  
  def favs_received(user)
    user.images.reduce(0){|favs, image| favs + image.favs.count}
  end
  
  def add_exif_data(image)
    exif_data = EXIFR::JPEG.new(open(image.file.url))
    if not exif_data.model.nil?
      image.exif_model = exif_data.model.to_s
    end
    if not exif_data.focal_length.nil?
      image.exif_focallength =  exif_data.focal_length.to_f.round.to_s
    end
    if not exif_data.iso_speed_ratings.nil?
      image.exif_iso =  exif_data.iso_speed_ratings.to_s
    end
    if not exif_data.f_number.nil?
      image.exif_aperture = exif_data.f_number.to_f.to_s
    end
    if not exif_data.exposure_time.nil?
      if (exif_data.exposure_time < 1)
        image.exif_shutterspeed = exif_data.exposure_time.to_s
      else
        image.exif_shutterspeed = "%.1f" %[exif_data.exposure_time.to_f]
      end
    end
    image.save
  end
end

# FILTERS
before do
  pass if ['/', '/signup', '/login', '/logout'].include?( request.path_info )
  if not login?
    redirect '/'
  end
end

# PUBLIC ROUTES
get '/' do
  if login?
    redirect '/images'
  end
  haml :index
end

post '/comments/:id' do
  image = Image.first(:id => params[:id])
  user = User.first(:name => session[:username])
  comment = Rinku.auto_link(Sanitize.clean(params['comment']), mode=:all, link_attr=nil, skip_tags=nil)
  Comment.create(:image => image, :user => user, :text => comment, :posted_at => Time.now)
  redirect back
end

get '/current_user_profile' do
  if user = User.first(:name => session[:username])
    redirect "/users/#{user.id}"
  end
  redirect back
end

post '/fav_image/:id' do
  if image = Image.first(:id => params[:id])
    if not ( has_faved_image?(image) or is_own_image?(image) )
      user = User.first(:name => session[:username])
      Fav.create(:image => image, :user => user)
    end
  end
  redirect '/'
end

get '/images' do 
  @images = Image.paginate(:page => params[:page],:order => [ :posted_at.desc ])
  haml :images
end

get '/images/:id' do
  if @image = Image.first(:id => params[:id])
    @fav_list = Fav.all(:image => @image)
    haml :image_details
  else
    redirect '/'
  end
end

post '/login' do
  if @user = User.first(:name => params[:username])
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

get '/signup' do
  haml :signup
end

post '/signup' do
  if not User.first(:name => params[:username])
    if not ValidateEmail.validate(params[:email], true)
      flash[:error] = "No valid email address given!"
      redirect back
    end
    if config_yaml['signup_code'] == params[:signupcode]   
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
  haml :upload
end
 
post '/upload' do 
  if not valid_ext?( File.extname(params['myfile'][:filename]).downcase )
    flash[:error] = "Wrong file type - not uploaded!"
    redirect '/images'
  end
  image = Image.create(:user => User.first(:name => session[:username]), :file => params['myfile'], :posted_at => Time.now)
  add_exif_data(image)
  redirect '/images'
end

get '/users' do
  @users = User.all
  haml :user_list
end

get '/users/:id' do
  @user = User.first(:id => params[:id])
  @images = @user.images.paginate(:page => params[:page],:order => [ :posted_at.desc ])
  haml :user_profile
end

#ADMINISTRATION ROUTES
post '/delete_image/:id' do
  if admin?
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
  if admin?
    haml :destroy
  else
    redirect '/'
  end
end

post '/destroy' do
  if admin?
    Image.all.each do |image|
      image.destroy!
    end    
    DataMapper.auto_migrate!
    CarrierWave.clean_cached_files!
    flash[:error] = "Database reset!"
  end
  redirect '/logout'
end

get '/recreate_image_versions' do
  if admin?
    Image.all.each do |image|
      puts image.file.recreate_versions!
    end
  end
  redirect '/'
end

get '/update_exif' do
  if admin?
    Image.all.each do |image|
      add_exif_data(image)
    end
  end
  redirect '/'
end