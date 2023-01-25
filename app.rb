require 'dotenv/load'

require 'sinatra' # Web server 
require 'sequel' # ORM
require 'octokit' # GH API wrapper
require 'base64' # Base64 decoding
require 'securerandom'

DB = Sequel.connect(ENV['DATABASE_URL']) 

def go_through_folder(prompt, client)
  contents = client.contents('hwchase17/langchain-hub', path: "#{prompt.path}")

  if contents.any? { |file| file.name == 'README.md' }
    readme = client.contents('hwchase17/langchain-hub', path: "#{prompt.path}/README.md")
    
    save_prompt_to_db(readme.content, readme.html_url)
  else
    contents.each do |prompt|      
      go_through_folder(prompt, client)
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
                  .gsub('## Inputs', '') # Ugly af, but it works. Not even Copilot Labs had any suggestions for this
                  .gsub('# Description of ', '') 

  DB[:LangChainPrompt].insert(
    id: SecureRandom.uuid,
    prompt: CGI.escape(prompt_info), # Doing this to preserve the newlines in the prompt
    githubPath: url,
    name: name,
    description: description.gsub("\n", ' '), # Remove newlines from the description
    readme: CGI.escape(decoded_readme)
  )
end

get '/update' do
  DB[:LangChainPrompt].delete

  client = Octokit::Client.new(access_token: ENV.fetch('GH_ACCESS_TOKEN'), page_size: 100)

  prompts = client.contents('hwchase17/langchain-hub', path: 'prompts')

  prompts.each do |prompt|
    next if prompt.type != 'dir' # Skip files (usually a README for all prompts)
        
    go_through_folder(prompt, client)
  end

  "All done!"
end
