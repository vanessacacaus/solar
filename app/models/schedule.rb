class Schedule < ActiveRecord::Base
  has_many :discussions
  has_many :lessons
  has_many :schedule_events
  has_many :portfolio


  def self.all_by_group_id_and_user_id_and_curriculum_unit_id( offer_id,group_id, user_id,curriculum_unit_id )
    ActiveRecord::Base.connection.select_all <<SQL
    WITH cte_all_allocations AS (

        -- descobrir todas as allocations
        WITH cte_allocations AS (
           SELECT t1.id           AS allocation_tag_id,
                  t1.curriculum_unit_id,
                  t1.offer_id,
                  t1.group_id
             FROM allocation_tags AS t1
             JOIN allocations     AS t2 ON t2.allocation_tag_id = t1.id
            WHERE t2.user_id = 5
              AND t2.status = 1
        ),
        -- descobrir todas as ofertas desses curriculum_units dessas allocations
        cte_offers_by_curriculum_unit AS (
            SELECT t1.allocation_tag_id,
                   t1.curriculum_unit_id,
                   t2.id           AS offer_id
              FROM cte_allocations AS t1
              JOIN offers          AS t2 ON t2.curriculum_unit_id = t1.curriculum_unit_id
        ),
        -- descobrir todos os grupos dessas ofertas
        cte_groups_by_offers_by_uc AS (
            SELECT t1.allocation_tag_id,
                   t1.curriculum_unit_id,
                   t1.offer_id,
                   t2.id AS group_id
              FROM cte_offers_by_curriculum_unit AS t1
              JOIN groups                        AS t2 ON t2.offer_id = t1.offer_id
        ),
        -- todas as allocation_tags da unidade curricular
        cte_allocations_by_uc AS (
            SELECT t1.id           AS allocation_tag_id,
                   t1.curriculum_unit_id,
                   t1.offer_id,
                   t1.group_id
              FROM allocation_tags AS t1
             WHERE t1.group_id           IN (SELECT group_id FROM cte_groups_by_offers_by_uc)
                OR t1.offer_id           IN (SELECT offer_id FROM cte_offers_by_curriculum_unit)
                OR t1.curriculum_unit_id IN (SELECT curriculum_unit_id FROM cte_allocations)
        ),
        -- descobrir todos os grupos dessas ofertas
        cte_groups_by_offers AS (
            SELECT t1.allocation_tag_id,
                   t1.curriculum_unit_id,
                   t1.offer_id,
                   t2.id           AS group_id
              FROM cte_allocations AS t1
              JOIN groups          AS t2 ON t2.offer_id = t1.offer_id
        ),
        -- allocations by offers
        cte_allocations_by_offers AS (
            SELECT t1.id           AS allocation_tag_id,
                   t1.curriculum_unit_id,
                   t1.offer_id,
                   t1.group_id
              FROM allocation_tags AS t1
             WHERE t1.group_id IN (SELECT group_id FROM cte_groups_by_offers)
                OR t1.offer_id IS NOT NULL
         )

        SELECT * FROM cte_allocations_by_uc
        UNION
        SELECT * FROM cte_allocations_by_offers
        UNION
        SELECT * FROM cte_allocations WHERE group_id IS NOT NULL
)

    SELECT * FROM (
      (    SELECT t1.name, t1.description, t4.start_date,t4.end_date , 'discussions' AS schedule_type
      FROM discussions AS t1
      JOIN schedules       AS t4 ON t1.schedule_id = t4.id
      JOIN allocation_tags AS t2 ON t2.id = t1.allocation_tag_id
      JOIN allocations     AS t3 ON t3.allocation_tag_id = t2.id
     WHERE t3.user_id = #{user_id}
      AND (t2.group_id = #{group_id}
      OR t2.offer_id = #{offer_id}
      OR t2.curriculum_unit_id = #{curriculum_unit_id})
      )
      union
      (    SELECT t1.name, t1.description, t4.start_date,t4.end_date, 'lessons' AS schedule_type
      FROM lessons AS t1
      JOIN schedules       AS t4 ON t1.schedule_id = t4.id
      JOIN allocation_tags AS t2 ON t2.id = t1.allocation_tag_id
      JOIN allocations     AS t3 ON t3.allocation_tag_id = t2.id
     WHERE t3.user_id = #{user_id}
      AND (t2.group_id = #{group_id}
      OR t2.offer_id = #{offer_id}
      OR t2.curriculum_unit_id = #{curriculum_unit_id})
      )
      union
      (
      SELECT t1.name,t1.enunciation AS description, t1.start_date,t1.end_date, 'assignments' AS schedule_type
      FROM assignments AS t1
      JOIN schedules       AS t4 ON t1.schedule_id = t4.id
      JOIN allocation_tags AS t2 ON t2.id = t1.allocation_tag_id
      JOIN allocations     AS t3 ON t3.allocation_tag_id = t2.id
     WHERE t3.user_id = #{user_id}
      AND (t2.group_id = #{group_id}
      OR t2.offer_id = #{offer_id}
      OR t2.curriculum_unit_id = #{curriculum_unit_id})
      )
      union
      (
      SELECT t1.title AS name,t1.description,t4.start_date,t4.end_date, 'schedule_events' AS schedule_type
      FROM schedule_events AS t1
      JOIN schedules       AS t4 ON t1.schedule_id = t4.id
      JOIN allocation_tags AS t2 ON t2.id = t1.allocation_tag_id
      JOIN allocations     AS t3 ON t3.allocation_tag_id = t2.id
     WHERE t3.user_id = #{user_id}
      AND (t2.group_id = #{group_id}
      OR t2.offer_id = #{offer_id}
      OR t2.curriculum_unit_id = #{curriculum_unit_id})
      )
) AS final

ORDER BY final.end_date 

SQL

  end
end
