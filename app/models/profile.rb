class Profile < ActiveRecord::Base
  include ActiveModel::ForbiddenAttributesProtection

  has_many :users, through: :allocations
  has_many :allocations, dependent: :restrict

  has_and_belongs_to_many :resources, join_table: "permissions_resources"

  after_create :copy_from_template, if: "not template.blank?"

  validates :description, :name, presence: true
  validates :name, length: {maximum: 255}
  validates :description, length: {maximum: 500}

  attr_accessor :template

  def has_type?(type)
    (self.types & type) == type
  end

  def all_resources
    Resource.joins("LEFT JOIN permissions_resources AS pr ON pr.resource_id = resources.id AND pr.profile_id = #{id}")
      .group("resources.controller, resources.action, resources.id, resources.description, pr.profile_id")
      .select("resources.id, resources.controller, resources.action, resources.description, pr.profile_id AS permission")
      .order("resources.controller, resources.description")
  end


  ## class methods


  def self.all_except_basic
    Profile.where("types <> ?", Profile_Type_Basic).order("name")
  end

  def self.student_profile
    find_by_types(Profile_Type_Student).id
  end

  private

    def copy_from_template
      self.resources << self.class.find(template).resources
    end

end
