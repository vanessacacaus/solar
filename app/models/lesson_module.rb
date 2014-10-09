class LessonModule < ActiveRecord::Base

  GROUP_PERMISSION, OFFER_PERMISSION = true, true

  # A ordem das instruções importa para execução
  before_destroy :verify_situation_module

  has_many :academic_allocations, as: :academic_tool, dependent: :destroy
  has_many :allocation_tags, through: :academic_allocations

  has_many :groups, through: :allocation_tags
  has_many :offers, through: :allocation_tags

  has_many :lessons, dependent: :destroy

  validates :name, presence: true

  accepts_nested_attributes_for :academic_allocations

  attr_accessible :academic_allocations_attributes, :name

  def verify_situation_module
   if lessons.count > 0  and academic_allocations.count > 1
     errors.add(:base, I18n.t(:cant_delete_shared, :scope => [:lesson_modules, :errors]))
     return false
   elsif is_default
     errors.add(:base, I18n.t(:cant_delete, :scope => [:lesson_modules, :errors]))
     return false
   end
  end

  def next_lesson_order
    lessons.maximum(:order).next rescue 1
  end

  def self.to_select(allocation_tags_ids, user = nil, list = false)
    user_is_admin_or_editor    = user.nil? ? false : (user.is_admin? or user.is_editor?)
    user_responsible = user.nil? ? false : user.profiles_with_access_on("see_drafts", "lessons", allocation_tags_ids, true).any?

    joins(:academic_allocations).where(academic_allocations: {allocation_tag_id: allocation_tags_ids}).order("id").delete_if { |lmodule|
      lessons               = lmodule.lessons
      has_open_lesson       = lessons.map(&:closed?).include?(false)

      only_responsible_sees = (lessons.collect{ |l| l if (l.will_open? or l.is_draft? or not(l.open_to_show? or list))}.compact).size

      lessons.empty? or (
        # nao eh admin nem responsavel
        not(user_is_admin_or_editor) and (not(user_responsible) and (only_responsible_sees == lessons.size) )
      ) or (
        not(list) and lessons.size == lessons.map{ |l| true if l.address.blank? }.compact.size
      ) or not(list or has_open_lesson)

    }.compact.uniq
  end

  def lessons_to_open(user = nil, list = false)
    user_is_admin_or_editor    = (user.is_admin? or user.is_editor?)
    user_responsible = user.nil? ? false : not(user.profiles_with_access_on("see_drafts", "lessons", self.allocation_tags.map(&:id), true).empty?)

    lessons.order("lessons.order").collect{ |lesson|
      lesson_with_address = (list or not(lesson.address.blank?))
      # if (lesson can open to show or list is true) or (is draft or will_open and is responsible) or user is admin
      lesson if ( user_is_admin_or_editor or (user_responsible and (lesson.is_draft? or lesson.will_open?) ) or (not(lesson.is_draft?) and ((list and not(lesson.will_open?)) or lesson.open_to_show?)) ) and lesson_with_address
    }.compact.uniq
  end

  def self.academic_allocations_by_ats(allocation_tags_ids, page: 1, per_page: 30)
    AcademicAllocation.select('DISTINCT ON (academic_tool_id) *').joins(:lesson_module)
      .where(allocation_tag_id: allocation_tags_ids)
      .order(:academic_tool_id)
      .paginate(page: page, per_page: per_page)
  end

end
