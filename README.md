# ImageBoard!
Simple *Instagram*-like **Sinatra Ruby web app** for posting images to your friends.

The app currently provides user authentication and registration, image upload & storage, comments and favs. 

The main purpose of this project for me is learning to develop simple web applications. Even if you are not specifically interested in image sharing, you can probably still find many components which you can resuse in or adapt to your own projects.

**This is an self-education project. If you find horrible bugs, security flaws, design decisions etc. please let me know!**

## Five steps to getting started

### (1) Install dependencies
The app uses the [Carrierwave](https://github.com/carrierwaveuploader/carrierwave) gem for image uploading. Carrierwave relies on [Imagemagick](http://www.imagemagick.org/script/index.php) for image resizing. On OS X you can install Imagemagick using [Homebrew](http://brew.sh): 

	brew install imagemagick
	
On the server you can e.g. install Imagemagick from the Ubuntu repositories:

	sudo apt-get install imagemagick


### (2) Install gems
The app is self-contained in the sense that you should get up & running by using

	bundle install
	
### (3) Amazon S3 configuration
In the current configuration the Imageboard app runs on a [DigitalOcean](https://www.digitalocean.com) server and images are stored at Amazon S3. The Amazon S3 upload is handled by Carrierwave via the [fog](https://github.com/fog/fog) gem. To use the app in this way you need to add a `config/fog_amazon_S3.yml`file where you add your S3 credentials.

The file should look similar to:
	
	# config/fog_amazon_S3.yml
	
	provider: 'AWS'
	aws_access_key_id: 'XYZ'
	aws_secret_access_key: 'XYZXYZ'
	region: 'eu-west-1'
	host: 'https://s3-eu-west-1.amazonaws.com/'
	endpoint: 'https://s3-eu-west-1.amazonaws.com'
	
If you prefer to store the image files locally on your server you can change the storage setting in the Image model definition in `server.rb`, i.e.:

	class ImageUploader < CarrierWave::Uploader::Base
  	  storage :file
  	  
  	  ...
  	  
  	end

### (4) Signup code & general configuration

I currently run the app ivite-only and require new users to use a signup-code for registration. The signup-code and some more configuration (motst important the name of **your Amazon S3 bucket**) are currently stored in `config/config.yml`:

	signup_code: 'mycode'
	cookie_secret: 'mysecret'
	S3bucket: 'myS3bucket'
	
### (5) Start the server
	
Try the app by starting the server with

	ruby server.rb
	
Browse to `http://localhost:4567`, create your account and start posting images!