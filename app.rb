require 'dotenv/load'

require 'sinatra' # Web server 
require 'sequel' # ORM
require 'octokit' # GH API wrapper
require 'base64' # Base64 decoding
require 'securerandom'

DB = Sequel.connect(ENV['DATABASE_URL']) 

def go_through_folder(prompt, client, object_type)
  contents = client.contents('hwchase17/langchain-hub', path: "#{prompt.path}")

  if contents.any? { |file| file.name == 'README.md' }
    readme = client.contents('hwchase17/langchain-hub', path: "#{prompt.path}/README.md")
    
    send("save_#{object_type}_to_db", readme.content, readme.html_url)
  else
    contents.each do |prompt|      
      go_through_folder(prompt, client, object_type)
    end
  end
end

def save_prompt_to_db(readme_content, url)
  decoded_readme = Base64.decode64(readme_content)

  name = decoded_readme.split("\n").first.gsub('# Description of ', '') # Name of the prompt is always in the first line of the README
  prompt_info = decoded_readme.split("## Inputs").last # All READMEs split the description from the inputs with a "## Inputs" header
  description = decoded_readme # Remove the name and prompt info from the README to get the description
                  .gsub(name, '')
                  .gsub(prompt_info, '')
                  .gsub('## Inputs', '') # Ugly, but it works. Not even Copilot Labs had any suggestions for this!
                  .gsub('# Description of', '')

  insert_object_in_db(
    :LangChainPrompt,
    { 
      prompt: prompt_info, # Doing this to preserve the newlines in the prompt
      githubPath: url,
      name: name,
      description: description.gsub("\n", ' '), # Remove newlines from the description as they are leftovers
      readme: decoded_readme
    } 
  )
end

def save_agent_to_db(readme_content, url)
  decoded_readme = Base64.decode64(readme_content)

  name = decoded_readme.split("\n").first.gsub('#', '') # Name of the prompt is always in the first line of the README

  type_and_tools = decoded_readme.split("## Agent type").last # All READMEs split the description from the rest with a "## Agent type" header
  
  agent_type, tools = type_and_tools.split("## Required Tool Names")

  description = decoded_readme # Remove the name and prompt info from the README to get the description
                  .gsub(name, '')
                  .gsub(type_and_tools, '')
                  .gsub('Agent type', '') # Ugly, but it works. Not even Copilot Labs had any suggestions for this!
                  .gsub('Description', '')
                  .gsub('#', '')

  insert_object_in_db(
    :LangChainAgent,
    { 
      agentType: agent_type, 
      requiredToolNames: tools,
      githubPath: url,
      name: name,
      description: description.gsub("\n", ' '), # Remove newlines from the description as they are leftovers
      readme: decoded_readme
    } 
  )
end

def insert_object_in_db(table, fields)
  DB[table].insert({id: SecureRandom.uuid}.merge(fields))
end

get '/update' do
  # Clear existing data. No need to do conflict resolution, just overwrite everything
  [:LangChainAgent, :LangChainPrompt].each { |t| DB[t].delete }

  client = Octokit::Client.new(access_token: ENV.fetch('GH_ACCESS_TOKEN'), page_size: 100)

  prompts = client.contents('hwchase17/langchain-hub', path: 'prompts')

  prompts.each do |prompt|
    next if prompt.type != 'dir' # Skip files (usually a README for all prompts)
        
    go_through_folder(prompt, client, :prompt)
  rescue => e # We just want to catch any errors and move on to the next one 
    puts "Error with a prompt: #{e.inspect}"
    next
  end

  agents = client.contents('hwchase17/langchain-hub', path: 'agents')

  agents.each do |prompt|
    next if prompt.type != 'dir' # Skip files (usually a README for all agents)
        
    go_through_folder(prompt, client, :agent)
  rescue => e # We just want to catch any errors and move on to the next one 
    puts "Error with an agent: #{e.inspect}"
    next
  end

  "All done!"
end