# Copyright (C) 2009 Pascal Rettig.


class Blog::BlogBlog < DomainModel

  before_validation :set_defaults, :on => :create

  validates_presence_of :name
  validates_presence_of :content_filter

  belongs_to :target, :polymorphic => true

  belongs_to :blog_target

  belongs_to :content_model
  belongs_to :content_publication

  has_many :blog_posts, :dependent => :destroy, :include => :active_revision
  has_many :blog_categories, :class_name => 'Blog::BlogCategory', :dependent => :destroy, :order => 'blog_categories.name'

  cached_content # Add cached content support 

  attr_accessor :add_to_site

  alias_method :targeted_blog, :target

  include SiteAuthorizationEngine::Target
  access_control :edit_permission
  
  serialize :options
  
  content_node_type :blog, "Blog::BlogPost", :content_name => :name,:title_field => :title, :url_field => :permalink, :except => Proc.new { |blg| blg.is_user_blog? }
  
  before_save :update_content_publication

  def self.create_user_blog(name,target)
    self.create(:name => name, :target => target, :is_user_blog => true)
  end

  def content_admin_url(blog_entry_id)
    {  :controller => '/blog/manage', :action => 'post', :path => [ self.id, blog_entry_id ],
       :title => 'Edit Blog Entry'.t}
  end

  def content_categories
    self.blog_categories
  end

  def content_category_nodes(category_id)
    ContentNode.all :conditions => {:node_type => 'Blog::BlogPost', :content_type_id => self.content_type.id, 'blog_posts_categories.blog_category_id' => category_id}, :joins => 'JOIN blog_posts_categories ON blog_post_id = node_id'
  end

  def paginate_posts_by_date(page,date_name,items_per_page,options = {})
    today = Time.now.at_midnight; end_time = Time.now
    case date_name.downcase
    when 'day':   start_time = today
    when 'week':  start_time = today - 7.days;
    when 'month': start_time = today.at_beginning_of_month
    when 'last_month': start_time = (today - 1.months).at_beginning_of_month; end_time = start_time.at_end_of_month
    when 'six_months': start_time = today - 6.months
    else return nil,[]
    end

    Blog::BlogPost.paginate(page,
                            { :include => [ :active_revision ],
                            :joins => [ :blog_posts_categories ],
                            :order => 'published_at DESC',
                            :conditions => [ "blog_posts.status = \"published\" AND blog_posts.blog_blog_id=? and published_at BETWEEN ? and ?",self.id,start_time,end_time],
                            :per_page => items_per_page }.merge(options))
  end                       


  def paginate_posts_by_category(page,cat,items_per_page,options = {})
    cat = [ cat] unless cat.is_a?(Array)

    category_ids = self.blog_categories.find(:all,:conditions => { :name => cat },:select=>'id').map(&:id)

    category_ids = [ 0] if category_ids.length == 0

    Blog::BlogPost.paginate(page,
                            { :include => [ :active_revision ],
                            :joins => [ :blog_posts_categories ],
                            :order => 'published_at DESC',
                            :conditions => [ "blog_posts.status = \"published\" AND blog_posts.published_at < ? AND blog_posts.blog_blog_id=? AND blog_posts_categories.blog_category_id in (?)",Time.now,self.id, category_ids],
                            :per_page => items_per_page }.merge(options))
  end                       


  def paginate_posts_by_tag(page,tag,items_per_page,options = {})

    tag = [ tag ] unless tag.is_a?(Array)

    tag_ids = ContentTag.find(:all,:conditions => { :name => tag },:select => 'id').map(&:id)
    tag_ids = [ 0 ] if tag_ids.length == 0

    Blog::BlogPost.paginate(page,
                            { :include => [ :active_revision ],
                            :joins => [ :content_tag_tags ],
                            :order => 'published_at DESC',
                            :conditions => ["blog_posts.status = \"published\" AND blog_posts.published_at < ? AND blog_posts.blog_blog_id=? AND content_tag_tags.content_tag_id in (?)",Time.now,self.id,tag_ids],
                            :per_page => items_per_page}.merge(options))
  end

  def paginate_posts_by_month(page,month,items_per_page,options = {})
    begin
      if month =~ /^([a-zA-Z]+)([0-9]+)$/
        tm = Time.parse($1 + " 1 " + $2)
      else
        return paginate_posts_by_date(page,month,items_per_page,options)
      end
    rescue Exception => e
      return nil,[]
    end

    Blog::BlogPost.paginate(page, {
			    :include => [ :active_revision, :blog_categories ],
			    :order => 'published_at DESC',
			    :conditions =>   ["blog_posts.status = \"published\" AND blog_posts.published_at < ? AND blog_posts.blog_blog_id=? AND blog_posts.published_at BETWEEN ? AND ?",Time.now,self.id,tm.at_beginning_of_month,tm.at_end_of_month],
			    :per_page => items_per_page }.merge(options))

  end

  def paginate_posts(page,items_per_page,options = {})
    Blog::BlogPost.paginate(page, {
                            :include => [ :active_revision ], 
                            :order => 'published_at DESC',
                            :conditions => ["blog_posts.status = \"published\" AND blog_posts.published_at < ?  AND blog_blog_id=?",Time.now,self.id],
                            :per_page => items_per_page }.merge(options))          

  end


  def find_post_by_permalink(permalink)
    self.blog_posts.most_recent.for_permalink(permalink).is_viewable.first
  end

  def content_type_name
    "Blog"
  end

  def self.filter_options
    ContentFilter.filter_options
  end

  def update_content_publication
    self.content_publication_id = nil if self.content_model.nil? || self.content_publication.nil? || self.content_model.id != self.content_publication.content_model_id
  end

  def set_defaults
    if self.is_user_blog?
      self.content_filter = 'safe_html' if self.is_user_blog?
      self.blog_target_id = Blog::BlogTarget.fetch_for_target(self.target)
    end
  end

  def send_pingbacks(post)
    return unless self.trackback? && post.published?
    post.run_pingbacks(post.active_revision.body_html)
  end

  @@import_fields  = %w(title permalink author published_at preview body embedded_media).map(&:to_sym)

  def import_file(domain_file,user)
     filename = domain_file.filename
     reader = CSV.open(filename,"r",',')
     file_fields = reader.shift
     reader.each do |row|
       args = {}
       @@import_fields.each_with_index { |fld,idx| args[fld] = row[idx] }

       post = self.blog_posts.find_by_permalink(args[:permalink]) if !args[:permalink].blank?

       args[:author] = user.name if args[:author].blank?
       post ||= self.blog_posts.build

       post.attributes = args
       post.publish(args[:published_at])  if !args[:published_at].blank?
       post.save
     end
  end
end
