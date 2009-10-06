require 'rubygems'
require 'sinatra'
require 'maglev/maglev_json'  # TODO: workaround for Trac 616

raise "==== Commit MDB Classes"  unless defined? MDB::Server

# Exception.install_debug_block do |e|
#   puts "--- #{e} #{e.class}"
#   case e
#   when RuntimeError
#     nil.pause if e.message =~ /Illegal creation of a Symbol/
#   end
# end

# REST interface to MaglevDB.  Accepts RESTful HTTP requests to access and
# manage the data stored in MDB.
=begin

  |--------+-----------------------------+-------------------------------|
  | Verb   | Collection                  | Member                        |
  |--------+-----------------------------+-------------------------------|
  | GET    | List members                | Get the member                |
  | PUT    | Replace collection          | Update member (edit)          |
  | POST   | Create new entry; return id | unclear                       |
  | DELETE | Delete entire collection    | Remove member from collection |
  |--------+-----------------------------+-------------------------------|

These requests correspond to methods on MDB::Server, a collection:

  |--------+-------+---------------------+-------------------|
  | Verb   | Route | Action              | View              |
  |--------+-------+---------------------+-------------------|
  | GET    | /     | List database names | Array of strings  |
  | PUT    | /     | NOT SUPPORTED       |                   |
  | POST   | /     | Database.create     | new id comes back |
  | DELETE | /     | NOT SUPPORTED       |                   |
  |        |       |                     |                   |
  | GET    | /:db  | Test if db exists   | boolean           |
  | PUT    | /:db  | NOT SUPPORTED       |                   |
  | POST   | /:db  | Create new document | id                |
  | DELETE | /:db  | Delete db           |                   |
  |--------+-------+---------------------+-------------------|

These requests correspond to methods on MDB::Database

  |--------+-------------------+------------------------------+--------------------|
  | Verb   | Route             | Action                       | View               |
  |--------+-------------------+------------------------------+--------------------|
  | GET    | /:db/:id          | Get document with :id        | the object as json |
  | PUT    | /:db/:id          | Update document :id          | status             |
  | POST   | /:db/:id          | NOT SUPPORTED                |                    |
  | DELETE | /:db/:id          | Delete document :id from :db | status             |
  |        |                   |                              |                    |
  | GET    | /:db/view/:name   | Run the view                 | data from view     |
  | GET    | /:db/send/:method | Send :method to ViewClass    | For testing        |
  |--------+-------------------+------------------------------+--------------------|

=end
#
# This class will ensure that all MDB level responses have properly formed
# JSON bodies, so it wraps everything in a JSON array.  The views should
# ensure they return just the subgraph they need (or create a hash of data)
# so that we do not JSON-ize the entire repository and send it back as a
# response...
class MDB::ServerApp < Sinatra::Base

  def initialize(*args)
    super
    @server = MDB::Server
  end

  before do
    Maglev.abort_transaction  # refresh view of db # TODO: Is this ok?
    content_type 'application/json'   # TODO  ; utf-8 ??
  end

  # This is here, rather than in the before block, since params does not
  # have the path info split out until after the before block is run.
  # Furthermore, not all paths will need the db.
  def get_db
    db = @server[params[:db]]
    halt 404, "No such Database: #{params[:db]}" if db.nil?
    db
  end

  # May need to wrap all of these in transactions.  At least need to abort
  # before handling most requests, since the DB may be updated from Rake or
  # another server.

  # List db names
  get '/' do
    # TODO: Currently raises: error , Illegal creation of a Symbol, when
    # trying to JSONize symbols, so convert to string first until Trac 616
    # is fixed.
    #jsonize @server.db_names.map { |name| name.to_s }
    jsonize @server.db_names
  end

  # Create a new database
  post '/' do
    jsonize @server.create(params[:db_name], params[:view_class])
  end

  # Query if db exists
  get '/:db' do
    jsonize @server.key? params[:db]
  end

  # Create new document
  # Create a new document for the database from form data.
  # The database will add the object to its collection, and then
  # call the model added(new_object) hook.
  post '/:db' do
    # .string is needed since request may be a StringIO,
    # and StringIO may not be committed to the repository.
    obj = from_json(request.body.string)
    jsonize get_db.add(obj)
    #jsonize get_db.add(request.body.string)
  end

  # Delete database
  # The server will delete the database.
  delete '/:db' do
    # .string is needed since request may be a StringIO,
    # and StringIO may not be committed to the repository.
    jsonize @server.delete params[:db]
  end

  # Get a document
  get '/:db/:id' do
    jsonize get_db.get(params[:id].to_i)
  end

  # Update a document
#   put '/:db/:id' do
#     jsonize get_db.put(params[:id].to_i, data)
#   end

  # Delete a document
  delete '/:db/:id' do
    jsonize get_db.delete params[:id].to_i
  end

  # Run a view on the database.
  # Returns view data.
  # On error, returns appropriate HTTP status code and error message.
  get '/:db/view/:view' do
    jsonize get_db.execute_view(params[:view])
  end

# TODO: /mdb is top level URL and represents the collection of dbs
#   POST /mdb  Create new db
  # For testing...
  get '/:db/send/:method' do
    jsonize get_db.send(params[:method].to_sym)
  end

  # We always wrap a response in an array, so that responses like bare
  # strings have a container.  The client assumes all responses are JSON
  # arrays, and will extract the first element as the content.
  def jsonize(obj)
    JSON.generate [obj]
  end

  def from_json(string)
    JSON.parse(string)[0]
  end
  # Or, we could do specific handlers such as:
  #    error MDB::DatabaseNotFound do
  #       # ...something specific for db not found errors
  #    end
  error do
    "MDB::ServerApp error: #{request.env['sinatra.error'].message}"
  end

  not_found do
    "MDB:ServerApp: unknown URL: #{request.path}"
  end
end