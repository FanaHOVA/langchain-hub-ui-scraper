# Setup database

require 'dotenv/load'
require 'sequel' # ORM

DB = Sequel.connect(ENV['DATABASE_URL']) 

DB.create_table :LangChainPrompt do
  uuid :id, primary_key: true
  String :name
  String :githubPath
  String :description
  String :prompt
  String :readme
end

DB.create_table :LangChainAgent do
  uuid :id, primary_key: true
  String :name
  String :githubPath
  String :description
  String :requiredToolNames
  String :agentType
  String :readme
end