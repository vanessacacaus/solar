class AssignmentFile < ActiveRecord::Base

  belongs_to :user
  belongs_to :send_assignment

  has_one :assignment, :through => :send_assignment

  validates :attachment_file_name, :presence => true

  has_attached_file :attachment,
    :path => ":rails_root/media/assignment/individual_area/:id_:basename.:extension",
    :url => "/media/assignment/individual_area/:id_:basename.:extension"

  validates :attachment_file_name, :presence => true
  validates_attachment_size :attachment, :less_than => 5.megabyte, :message => " "
  validates_attachment_content_type_in_black_list :attachment

  ##
  # Deleta arquivo
  ##
  def delete_assignment_file
    begin
      file = "#{::Rails.root.to_s}/media/assignment/individual_area/#{id}_#{attachment_file_name}" #recupera arquivo
      if delete #se deletar arquivo da base de dados com sucesso
        File.delete(file) if File.exist?(file) #deleta arquivo do servidor
      else
        flash[:alert] = t(:error_delete, :scope => [:portfolio, :files])
      end
    rescue Exception => error
      flash[:alert] = error.message
    end
  end

end
