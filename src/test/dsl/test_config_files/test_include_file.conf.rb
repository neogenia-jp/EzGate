# include_file のテスト
include_file 'included.conf.rb'

domain('primary.example.com') do
  no_ssl
end
