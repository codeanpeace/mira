admin_email = 'harrison@avhana.com'

u = User.where(email: admin_email)
if u.empty?
  user = User.create! :email => admin_email, :password => 'topsecret', :password_confirmation => 'topsecret'
end

