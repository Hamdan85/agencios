# frozen_string_literal: true

require 'rails_helper'

# The Epidemic Sound MCP client (Streamable HTTP / JSON-RPC 2.0). It opens a
# session, searches the catalog (SearchRecordings), resolves a burnable download
# URL (DownloadRecording), and normalizes to the shared music-track contract.
RSpec.describe Vendors::EpidemicSound::Client do
  subject(:client) { described_class.new(api_key: 'key-123') }

  attr_reader :search_args, :download_args

  def response(body:, headers: {}, success: true, status: 200)
    instance_double(Faraday::Response, success?: success, body: body, status: status, headers: headers)
  end

  def tool_result(payload) = { 'content' => [], 'structuredContent' => payload }

  # A SearchRecordings result: data.recordings.nodes[].recording.
  def recordings(*recs)
    { 'data' => { 'recordings' => { 'nodes' => recs.map { |r| { 'recording' => r } } } } }
  end

  # Fake the Faraday boundary (project convention): a single connection whose
  # #post routes by the JSON-RPC method + tool name in the captured body.
  def stub_mcp(search:, download:)
    conn = instance_double(Faraday::Connection)
    allow(conn).to receive(:post) do |&blk|
      req = double('req')
      body = nil
      allow(req).to receive(:body=) { |b| body = b.deep_stringify_keys }
      allow(req).to receive(:headers).and_return({})
      blk.call(req)

      case body['method']
      when 'initialize'
        response(body: { 'jsonrpc' => '2.0', 'id' => body['id'], 'result' => { 'serverInfo' => {} } },
                 headers: { 'mcp-session-id' => 'sess-1' })
      when 'notifications/initialized'
        response(body: '', status: 202)
      when 'tools/call'
        tool = body.dig('params', 'name')
        args = body.dig('params', 'arguments')
        if tool == 'SearchRecordings'
          @search_args = args
          response(body: { 'jsonrpc' => '2.0', 'id' => body['id'], 'result' => tool_result(search) })
        else
          @download_args = args
          download.is_a?(Exception) ? raise(download) : response(body: { 'jsonrpc' => '2.0', 'id' => body['id'], 'result' => tool_result(download) })
        end
      end
    end
    allow(client).to receive(:connection).and_return(conn)
  end

  let(:sample) do
    { 'id' => 'uuid-1', 'title' => 'Golden Hour', 'coverArtUrl' => 'https://cdn/cover.png',
      'audioFile' => { 'durationInMilliseconds' => 132_000 },
      'credits' => [{ 'role' => 'COMPOSER', 'artist' => { 'name' => 'X' } },
                    { 'role' => 'MAIN_ARTIST', 'artist' => { 'name' => 'Bell' } }] }
  end

  it 'is not configured without an api key' do
    expect(described_class.new(api_key: nil).configured?).to be(false)
  end

  it 'searches by semantic topic (vocals filtered out) and normalizes the best track' do
    stub_mcp(search: recordings(sample), download: { 'data' => { 'recordingDownload' => { 'url' => 'https://cdn/gold.mp3' } } })

    track = client.search(query: 'warm indie folk', tags: 'happy').first

    expect(search_args['query']).to eq('topic' => 'warm indie folk, happy')
    expect(search_args['filter']).to eq('vocals' => false)
    expect(download_args).to include('id' => 'uuid-1', 'options' => { 'fileType' => 'MP3', 'stemType' => 'FULL' })
    expect(track).to include(
      id: 'uuid-1', title: 'Golden Hour', artist: 'Bell',
      url: 'https://cdn/gold.mp3', image_url: 'https://cdn/cover.png',
      attribution: 'Golden Hour — Bell', duration: 132, license: 'Epidemic Sound'
    )
  end

  it 'yields nothing when the download is FORBIDDEN (unentitled key)' do
    stub_mcp(search: recordings(sample),
             download: Vendors::Base::Error.new('You don\'t have permission to download this asset'))

    expect(client.search(query: 'ambient')).to eq([])
  end
end
