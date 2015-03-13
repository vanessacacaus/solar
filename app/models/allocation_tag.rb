class AllocationTag < ActiveRecord::Base

  belongs_to :course
  belongs_to :curriculum_unit_type
  belongs_to :curriculum_unit
  belongs_to :offer
  belongs_to :group

  has_many :schedule_events
  has_many :allocations, dependent: :destroy
  has_many :academic_allocations, dependent: :restrict # nao posso deletar uma ferramenta academica se tiver conteudo

  has_many :users, through: :allocations, uniq: true

  has_many :savs, dependent: :destroy

  def groups
    case refer_to
      when 'group'
        [group]
      when 'offer'
        Group.where(offer_id: offer_id)
      when 'curriculum_unit'
        Group.joins(:offer).where(offers: {curriculum_unit_id: curriculum_unit_id})
      when 'course'
        Group.joins(:offer).where(offers: {course_id: course_id})
      when 'curriculum_unit_type'
        Group.joins(offer: :curriculum_unit).where(curriculum_units: {curriculum_unit_type_id: curriculum_unit_type_id})
    end
  end

  def offers
    case refer_to
      when 'group'
        Offer.joins(:groups).where(groups: {id: group_id})
      when 'offer'
        [offer]
      when 'curriculum_unit'
        Offer.where(curriculum_unit_id: curriculum_unit_id)
      when 'course'
        Offer.where(course_id: course_id)
      when 'curriculum_unit_type'
        Offer.joins(:curriculum_unit).where(curriculum_units: {curriculum_unit_type_id: curriculum_unit_type_id})
    end
  end

  def is_responsible?(user_id)
    check_if_user_has_profile_type(user_id)
  end

  def is_observer_or_responsible?(user_id)
    check_if_user_has_profile_type(user_id, responsible = true, observer = true)
  end

  ## return group, offer, course or curriculum_unit
  def refer_to
    self.attributes.keep_if {|k,v| k != "id" and not(v.nil?)}.keys.first.sub(/\_id/, '')
  end

  def is_student?(user_id)
    allocations.joins(:profile).where(user_id: user_id, status: Allocation_Activated).where('cast(profiles.types & ? as boolean)', Profile_Type_Student).count > 0
  end

  def is_student_or_responsible?(user_id)
    check_if_user_has_profile_type(user_id, responsible = true, observer = false, student = true)
  end

  def info
    self.send(refer_to).try(:info)
  end

  def detailed_info
    self.send(refer_to).try(:detailed_info)
  end

  def curriculum_unit_types
    case refer_to
      when 'group'
        CurriculumUnitType.joins(curriculum_units: {offers: :groups}).where(groups: {id: group_id}).first.description
      when 'offer'
        CurriculumUnitType.joins(curriculum_units: :offers).where(offers: {id: offer_id}).first.description
      when 'curriculum_unit'
        CurriculumUnitType.joins(:curriculum_units).where(curriculum_units: {id: curriculum_unit_id}).first.description
      when 'course'; ''
      when 'curriculum_unit_type'
        curriculum_unit_type.description
    end
  rescue
    I18n.t('users.profiles.not_specified')
  end

  ## ex: '2014.2 2015.1 semester_active'
  def semester_info
    s_info = case refer_to
    when 'group'
      g_offer = offers.first
      [g_offer.semester.name, ('semester_active' if g_offer.is_active?)]
    when 'offer'
      [offer.semester.name, ('semester_active' if offer.is_active?)]
    when 'curriculum_unit', 'course', 'curriculum_unit_type'
      c_offers  = offers
      semesters = Semester.joins(:offers).where(offers: {id: c_offers.map(&:id)})
      [semesters.map(&:name).uniq.join(' '), ('semester_active' if c_offers.map(&:is_active?).include?(true))]
    end

    s_info.compact.join(' ')
  end

  def related(options = { upper: true, lower: true })
    RelatedTaggable.related(self, options)
  end

  def lower_related
    related(lower: true)
  end

  def self.at_groups_by_offer_id(offer_id, only_id = true)
    RelatedTaggable.where(offer_id: offer_id).pluck(:group_at_id).uniq
  end

  def self.get_by_params(params, related = false, lower_related = false)
    allocation_tags_ids, selected, offer_id = unless params[:allocation_tags_ids].blank? # o proprio params ja contem as ats
      [params.fetch(:allocation_tags_ids, '').split(' ').flatten.map(&:to_i), params.fetch(:selected, nil), params.fetch(:offer_id, nil)]
    else
      case 
        when !params[:groups_id].blank?
          params[:groups_ids] = params[:groups_id].split(" ").flatten.map(&:to_i)
          query = 'group_id IN (:groups_ids)'
          selected = 'GROUP'
          offer = true
        when !params[:semester_id].blank? || !params[:semester].blank?
          query = []
          params.merge!(semester_id: Semester.where(name: params[:semester]).first.try(:id)) unless params[:semester_id]
          raise ActiveRecord::RecordNotFound unless params[:semester_id]
          query << 'semester_id = :semester_id'
          query << 'curriculum_unit_id = :curriculum_unit_id' if params[:curriculum_unit_id]
          query << 'course_id = :course_id' if params[:course_id]
          query << 'curriculum_unit_type_id = :curriculum_unit_type_id' if params[:curriculum_unit_type_id]
          query = query.join(" AND ")
          selected = 'OFFER'
          offer = true
        when !params[:offer_id].blank?
          query = []
          query << 'offer_id = :offer_id'
          selected = 'OFFER'
          offer = true
        when !params[:course_id].blank?
          query = 'course_id = :course_id'
          selected = 'COURSE'
        when !params[:curriculum_unit_id].blank?
          query = 'curriculum_unit_id = :curriculum_unit_id'
          selected = 'CURRICULUM_UNIT'
        when !params[:curriculum_unit_type_id].blank?
          query = 'curriculum_unit_type_id = :curriculum_unit_type_id'
          selected = 'CURRICULUM_UNIT_TYPE'
      end

      unless query.blank?
        rts = RelatedTaggable.where(query, params.slice(:groups_ids, :offer_id, :semester_id, :course_id, :curriculum_unit_id, :curriculum_unit_type_id))
        raise ActiveRecord::RecordNotFound if rts.empty?

        offer_id = rts.map(&:offer_id).first if offer
        opt = (lower_related ? { lower: true } : ((related || selected.nil?) ? {} : { name: selected.downcase }))
        [rts.map{|rt| rt.at_ids(opt)}.uniq, selected, offer_id]
      end
    end

    {allocation_tags: [allocation_tags_ids].flatten, selected: selected, offer_id: offer_id}
  end

  def self.get_participants(allocation_tag_id, params = {})
    types, query = [], []
    types << "cast( profiles.types & '#{Profile_Type_Student}' as boolean )"           if params[:students]     or params[:all]
    types << "cast( profiles.types & '#{Profile_Type_Class_Responsible}' as boolean )" if params[:responsibles] or params[:all]
    query << "profile_id IN (#{params[:profiles]})"                                    if params[:profiles]

    ats = (allocation_tag_id.kind_of?(Array) ? allocation_tag_id : AllocationTag.find(allocation_tag_id).related)

    User.select("users.*, COUNT(public_files.id) AS u_public_files, replace(replace(translate(array_agg(distinct profiles.name)::text,'{}', ''),'\"', ''),',',', ') AS profile_name")
      .joins(allocations: :profile)
      .joins("LEFT JOIN public_files ON public_files.user_id = users.id AND public_files.allocation_tag_id IN (#{ats.flatten.join(",")})")
      .where(allocations: { status: Allocation_Activated, allocation_tag_id: ats })
      .where(types.join(' OR ')).where(query.join(' AND ')).uniq
      .group('users.id, users.name').order('users.name')
  end

  ### triggers

  trigger.after(:insert) do
    <<-SQL
      -- groups
      IF (NEW.group_id IS NOT NULL) THEN
        INSERT INTO related_taggables (group_id, group_at_id, group_status, offer_id, offer_at_id, semester_id,
                    curriculum_unit_id, curriculum_unit_at_id, course_id, course_at_id, curriculum_unit_type_id, curriculum_unit_type_at_id, offer_schedule_id)
          SELECT * FROM vw_at_related_groups WHERE group_id = NEW.group_id;
      -- offers
      ELSIF (NEW.offer_id IS NOT NULL) THEN
        INSERT INTO related_taggables (offer_id, offer_at_id, semester_id, curriculum_unit_id, curriculum_unit_at_id,
                    course_id, course_at_id, curriculum_unit_type_id, curriculum_unit_type_at_id, offer_schedule_id)
          SELECT * FROM vw_at_related_offers WHERE offer_id = NEW.offer_id;
      -- courses
      ELSIF (NEW.course_id IS NOT NULL) THEN
        INSERT INTO related_taggables (course_id, course_at_id) VALUES (NEW.course_id, NEW.id);
      -- UC
      ELSIF (NEW.curriculum_unit_id IS NOT NULL) THEN
        INSERT INTO related_taggables (curriculum_unit_id, curriculum_unit_at_id, curriculum_unit_type_id, curriculum_unit_type_at_id)
          SELECT * FROM vw_at_related_curriculum_units WHERE curriculum_unit_id = NEW.curriculum_unit_id;
      -- UC type
      ELSIF (NEW.curriculum_unit_type_id IS NOT NULL) THEN
        INSERT INTO related_taggables (curriculum_unit_type_id, curriculum_unit_type_at_id) VALUES (NEW.curriculum_unit_type_id, NEW.id);
      END IF;
    SQL
  end

  trigger.after(:destroy) do
    <<-SQL
      DELETE FROM related_taggables
            WHERE group_at_id = OLD.id
               OR offer_at_id = OLD.id
               OR course_at_id = OLD.id
               OR curriculum_unit_at_id = OLD.id
               OR curriculum_unit_type_at_id = OLD.id;
    SQL
  end

  private

    def check_if_user_has_profile_type(user_id, responsible = true, observer = false, student = false)
      query = {
        user_id: user_id,
        status: Allocation_Activated,
        allocation_tag_id: self.related(upper: true),
        profiles: { status: true }
      }

      query_type = []
      query_type << 'cast(profiles.types & :responsible as boolean) OR cast(profiles.types & :coord as boolean)' if responsible
      query_type << 'cast(profiles.types & :observer as boolean)' if observer
      query_type << 'cast(profiles.types & :student as boolean)' if student

      return false if query_type.empty?

      Allocation.joins(:profile)
        .where(query)
        .where(query_type.join(' OR '), responsible: Profile_Type_Class_Responsible, observer: Profile_Type_Observer, coord: Profile_Type_Coord, student: Profile_Type_Student).count > 0
    end

end
