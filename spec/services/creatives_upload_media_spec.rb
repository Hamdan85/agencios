# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Creatives, '.accepted_upload_media' do
  it 'accepts only video for video types' do
    expect(described_class.accepted_upload_media('reel')).to eq(%w[video])
    expect(described_class.accepted_upload_media('ugc_video')).to eq(%w[video])
  end

  it 'accepts only images for image/carousel types' do
    expect(described_class.accepted_upload_media('feed_image')).to eq(%w[image])
    expect(described_class.accepted_upload_media('carousel')).to eq(%w[image])
    expect(described_class.accepted_upload_media('ad')).to eq(%w[image])
    expect(described_class.accepted_upload_media('thumbnail')).to eq(%w[image])
  end

  it 'accepts either for a story (IG/FB stories can be image or video)' do
    expect(described_class.accepted_upload_media('story')).to contain_exactly('image', 'video')
  end

  it 'defaults a coverless/unknown kind to images' do
    expect(described_class.accepted_upload_media('cover')).to eq(%w[image])
    expect(described_class.accepted_upload_media('unknown')).to eq(%w[image])
  end
end
