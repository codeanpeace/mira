

# Mira

Mira is developed using Ruby on Rails. You upload CSV files to it and it *tries* to give you a read-only HTTP API (if it likes the files you upload ;)) 

CSV files are uploaded to Mira along with a corresponding tabular data package (a datapackage.json file). The datapackage.json file provides the CSV file metadata, i.e. file names, columns, column-types, delimiters etc. See [here](http://data.okfn.org/doc/tabular-data-package) and [here](http://dataprotocols.org/tabular-data-package/) for more information on tabular data packages.


## Quick Start

#### Pre-requisites
- Ruby is installed (the version in Gemfile). Installing using RVM could be a good idea

  [https://www.ruby-lang.org/en/] (https://www.ruby-lang.org/en/)

  [https://rvm.io/] (https://rvm.io/)

- postgresql is installed

  [https://www.digitalocean.com/community/tutorials/how-to-use-postgresql-with-your-ruby-on-rails-application-on-ubuntu-14-04] (https://www.digitalocean.com/community/tutorials/how-to-use-postgresql-with-your-ruby-on-rails-application-on-ubuntu-14-04)

  Suggest creating a user called "mira"

- install the bundler gem

  gem install bundler


---

1. Clone the repository

2. Run bundle

        bundle install

3. Update the config/database.yml file with your database credentials

        default: &default
          adapter: postgresql
          encoding: unicode
          pool: 5
          host: localhost
          port: 5432
          **username: mira**
          **password: your_password**

4. Create and migrate database, and seed database with a single admin user (email = admin@example.com and password = topsecret):

        rake db:create
        rake db:migrate
        rake db:seed

5. Start your local development server

        rails s

6. In a separate terminal start a background job to process uploaded files

        rake jobs:work

7. Open up the Mira homepage:

    [http://localhost:3000] (http://localhost:3000)

8. Download sample csv files + their datapackage.json file:

    [https://github.com/davbre/dummy-sdtm/blob/master/output/mira_sample_data/mira_sample_data.tar.gz] (tar.gz file)
    [https://github.com/davbre/dummy-sdtm/blob/master/output/mira_sample_data/mira_sample_data.zip] (zip file)

9. Log in, create a new project, upload the sample csv files + datapackage.json file (from previous step)

10. Navigate to the following address for the project's API details:

    [http://localhost:3000/projects/1/api-details] (http://localhost:3000/projects/1/api-details)


## Demo

http://46.101.208.152

API details of an example project:
http://46.101.208.152/projects/1/api-details
