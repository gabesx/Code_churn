# frozen_string_literal: true

# Require necessary libraries
require 'httparty' # For making HTTP requests
require 'date'     # For handling dates
require 'csv'      # For CSV file operations

# Configuration variables sourced from environment variables for security and flexibility
# Fallback to default GitLab API URL if not set in ENV
GITLAB_API_URL = ENV['GITLAB_API_URL'] || 'https://gitlab.com/api/v4' 
# Project ID to fetch merge requests for
PROJECT_ID = ENV['GITLAB_PROJECT_ID'] 
# Personal Access Token for authentication
ACCESS_TOKEN = ENV['GITLAB_ACCESS_TOKEN'] 


# Fetch all merge requests from the specified GitLab project
def fetch_merge_requests(project_id)

  # Set the private token for authorization
  headers = { 'PRIVATE-TOKEN': ACCESS_TOKEN } 

  # Initialize an array to store merge requests
  merge_requests = [] 
  # Start from the first page
  page = 1 

  loop do
    puts "Fetching merge requests, page: #{page}"
    response = HTTParty.get("#{GITLAB_API_URL}/projects/#{project_id}/merge_requests",
                            headers: headers,
                            query: { state: 'all', scope: 'all', per_page: 100, page: page })  # Fetch merge requests
    break unless response.success?

    # Add the fetched merge requests to the array
    merge_requests.concat(response.parsed_response) 

    # Break the loop if there are no more pages
    break if response.headers['x-next-page'].to_s.empty? 

    # Increment the page number for the next iteration
    page += 1 
  end

  merge_requests # Return the collected merge requests
end

# Fetch changes for a specific merge request
def fetch_merge_request_changes(project_id, merge_request_iid)
  # Set the private token for authorization
  headers = { 'PRIVATE-TOKEN': ACCESS_TOKEN } 

  # Fetch changes for the merge request
  response = HTTParty.get("#{GITLAB_API_URL}/projects/#{project_id}/merge_requests/#{merge_request_iid}/changes",
                          headers: headers) 
  return [] unless response.success?

  changes_response = response.parsed_response
  file_changes = [] # Initialize an array to store file changes
  total_added = 0 # Initialize a counter for total lines added
  total_removed = 0 # Initialize a counter for total lines removed

  if changes_response['changes']
    changes_response['changes'].each do |change|
      added_lines = change['diff'].scan(/^\+/).count # Count added lines
      removed_lines = change['diff'].scan(/^-/).count # Count removed lines
      total_added += added_lines # Update total added lines
      total_removed += removed_lines # Update total removed lines

      # Store file change information
      file_change = {
        file_path: change['old_path'],
        added_lines: added_lines,
        removed_lines: removed_lines
      }
      file_changes << file_change # Add the file change to the array
    end
  end

  # Return file changes and totals
  { file_changes: file_changes, total_added: total_added, total_removed: total_removed }
end

# Get detailed information for all merge requests in the project
def get_detailed_mr_info(project_id)
  merge_requests = fetch_merge_requests(project_id) # Fetch all merge requests
  merge_requests.map do |mr|
    puts "Processing MR IID: #{mr['iid']}"
    changes_data = fetch_merge_request_changes(project_id, mr['iid']) # Fetch changes for each merge request
    # Collect and return detailed information for the merge request
    {
      author: mr['author']['username'],
      iid: mr['iid'],
      start_time: mr['created_at'],
      state: mr['state'],
      file_changes: changes_data[:file_changes],
      total_added: changes_data[:total_added],
      total_removed: changes_data[:total_removed],
      merged_time: mr['merged_at'],
      branch_name: mr['source_branch']
    }
  end
end

# Write detailed merge request information to a CSV file
def write_to_csv(detailed_info)
  CSV.open("merge_requests.csv", "w", write_headers: true, headers: ["MR IID", "Branch", "Author", "Start Time", "State", "Merged Time", "Total Added Lines", "Total Removed Lines", "File Changes"]) do |csv|
    detailed_info.each do |info|
      file_changes_str = info[:file_changes].map { |change| "#{change[:file_path]}: +#{change[:added_lines]}/-#{change[:removed_lines]}" }.join("; ")
      csv << [info[:iid], info[:branch_name], info[:author], info[:start_time], info[:state], info[:merged_time], info[:total_added], info[:total_removed], file_changes_str]
    end
  end
end

begin
  detailed_info = get_detailed_mr_info(PROJECT_ID)
  # write data to CSV
  write_to_csv(detailed_info) 
rescue StandardError => e
  puts "An error occurred: #{e.message}"
end
