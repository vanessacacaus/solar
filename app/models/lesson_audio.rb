class LessonAudio < ActiveRecord::Base
  belongs_to :lesson

   has_attached_file :audio,
                    path: ':rails_root/media/lessons/:lesson_id/audios/:normalized_audio_file_name',
                    url: '/media/lessons/:lesson_id/audios/:normalized_audio_file_name'            

  validates :audio, presence: true
  validates :count_text, presence: true, unless: -> {main.blank?}

  validates_attachment_size :audio, less_than: 50.megabyte, message: ''
  validates_attachment_content_type :audio, content_type: /^audio\/(mpeg|x-mpeg|mp3|x-mp3|mpeg3|x-mpeg3|mpg|x-mpg|x-mpegaudio)$/, message: I18n.t('questions.error.wrong_type_audio')

  
  before_save :replace_audio

  def self.list(lesson_id)
    LessonAudio.where(lesson_id: lesson_id)
      .select('DISTINCT lesson_audios.id, lesson_audios.audio_file_name, lesson_audios.audio_content_type, lesson_audios.audio_file_size, lesson_audios.audio_updated_at, count_text, main')
  end

  Paperclip.interpolates :normalized_audio_file_name do |attachment, style|
    attachment.instance.normalized_audio_file_name
  end

  def normalized_audio_file_name
    audio_name= audio_file_name.split('.')
    extension = audio_name.last
    audio_name.pop
    audio_name_2 = audio_name.to_sentence(two_words_connector: '_')
   "#{audio_name_2.gsub( /[^a-zA-Z0-9_\.]/, '_')}.#{extension}"
  end

  def self.normalized_text(text)
    name_2 = text.to_sentence(two_words_connector: '_')
    name_2.gsub( /[^a-zA-Z0-9_\.]/, '_')
  end  


  def self.text_to_speech(text_topico, text, lesson_id)
    name_topico = text_topico.gsub( /[^a-zA-Z0-9_\.]/, '_')
    
    audio_path_last = File.expand_path File.join("#{Rails.root}", 'media', "lessons/#{lesson_id.to_s}/audios/#{name_topico}.mp3")
    array_audio_path = Array.new
    idx = 0
    count_text = 0
    array_texts = text.chars.each_slice(5000).to_a.map {|s| s.join }
    array_texts.to_a.each do |t|
      path = File.expand_path File.join("#{Rails.root}", 'media', "lessons/#{lesson_id.to_s}/audios/#{name_topico}_#{idx.to_s}.mp3")
      array_audio_path.push(path)
      LessonAudio.generate_text_to_audio(t, path)
      count_text += t.to_s.length
      idx = idx + 1
    end  
    LessonAudio.concatenate_audio(array_audio_path, audio_path_last)
    lessonaudio = LessonAudio.new({lesson_id: lesson_id, count_text: count_text, main: false}) 
    lessonaudio.audio = File.new(audio_path_last) 
    lessonaudio.audio.save                          
    lessonaudio.save!
    audio_path_last
  end

  require "google/cloud/text_to_speech"
  def self.generate_text_to_audio(text, path, language="pt-BR")
    
    client = Google::Cloud::TextToSpeech.new
    input = { text: text }
    voice = {
      language_code: language,
      ssml_gender:   "FEMALE"
    }
    audio_config = { audio_encoding: "MP3" }
    response = client.synthesize_speech(input, voice, audio_config)
    File.open(path, "wb") do |file|
      file.write(response.audio_content)
    end
  end

  def self.concatenate_audio(array_audio_path, audio_path_last)
    sox_command = "sox --combine sequence "
    array_audio_path.each do |track|
      sox_command = sox_command + ' ' + track + " "
    end
    sox_command += audio_path_last
    system sox_command
  end

  def self.count_text_month(month=nil, year=nil)
    month =  Date.today.strftime("%m") if month.nil?
    year =  Date.today.strftime("%Y") if year.nil?
    lesson_audio = LessonAudio.where("to_char(created_at,'YYYY-MM')=? AND main=?", year+'-'+month,  true).select("SUM(count_text) AS count_text").limit(1)
    lesson_audio[0].count_text.nil? ? 0 : lesson_audio[0].count_text
  end

  private
  def replace_audio
    self.audio_file_name = normalized_audio_file_name
  end

end
