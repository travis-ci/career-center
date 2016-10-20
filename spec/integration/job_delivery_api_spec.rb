# frozen_string_literal: true
describe 'Job Delivery API', integration: true do
  let(:auth) { %w(guest guest) }
  let(:auth_tokens) { %w(abc123 secret) }

  before do
    allow_any_instance_of(JobBoard::JWTJobIDAuth).to receive(:alg)
      .and_return('none')
    allow_any_instance_of(JobBoard::JWTJobIDAuth).to receive(:secret)
      .and_return(nil)
    allow_any_instance_of(JobBoard::JWTJobIDAuth).to receive(:verify)
      .and_return(false)
    allow_any_instance_of(JobBoard::Auth).to receive(:auth_tokens)
      .and_return(auth_tokens)
    allow_any_instance_of(JobBoard::Services::CreateJob)
      .to receive(:assign_queue).and_return('lel')
    allow_any_instance_of(JobBoard::Services::FetchJob)
      .to receive(:fetch_job_script).and_return("#!/bin/bash\necho flah\n")
    allow_any_instance_of(JobBoard::Services::FetchJob)
      .to receive(:generate_jwt).and_return('FAFAFAF.BABABAB.DADADAD')
    allow_any_instance_of(JobBoard::Services::CreateJWT)
      .to receive(:private_key).and_return(nil)
    allow_any_instance_of(JobBoard::Services::CreateJWT)
      .to receive(:alg).and_return('none')
  end

  describe 'POST /jobs' do
    before :each do
      JobBoard::Models::Job.where(queue: 'lel').delete
      JobBoard::Models.redis.del('queue:lel')
      JobBoard::Models.redis.srem('queues', 'lel')

      3.times do |n|
        JobBoard::Services::CreateJob.run(
          params: {
            'id' => "#{Time.now.to_i}#{n}"
          }
        )
      end
      authorize(*auth)
    end

    after :each do
      JobBoard::Models::Job.where(queue: 'lel').delete
    end

    it 'returns 200' do
      post '/jobs?queue=lel&count=3', JSON.dump(jobs: []),
           'HTTP_CONTENT_TYPE' => 'application/json',
           'HTTP_FROM' => 'worker+test@localhost'
      expect(last_response.status).to eq(200)
    end

    it 'includes count metadata' do
      post '/jobs?queue=lel&count=3', JSON.dump(jobs: []),
           'HTTP_CONTENT_TYPE' => 'application/json',
           'HTTP_FROM' => 'worker+test@localhost'
      response_body = JSON.parse(last_response.body)
      expect(response_body['@count']).to eq(3)
    end

    it 'includes queue metadata' do
      post '/jobs?queue=lel&count=3', JSON.dump(jobs: []),
           'HTTP_CONTENT_TYPE' => 'application/json',
           'HTTP_FROM' => 'worker+test@localhost'
      response_body = JSON.parse(last_response.body)
      expect(response_body['@queue']).to eq('lel')
    end

    it 'returns the expected number of jobs' do
      post '/jobs?queue=lel&count=3', JSON.dump(jobs: []),
           'HTTP_CONTENT_TYPE' => 'application/json',
           'HTTP_FROM' => 'worker+test@localhost'
      response_body = JSON.parse(last_response.body)
      expect(response_body['jobs']).to_not be_nil
      expect(response_body['jobs'].length).to eq(3)
      expect(response_body['unavailable_jobs'].length).to eq(0)
    end
  end

  describe 'POST /jobs/add' do
    let :job do
      {
        '@type' => 'job',
        'id' => Time.now.to_i.to_s,
        'language' => 'rubby',
        'os' => 'lanerks'
      }
    end

    before :each do
      JobBoard::Models::Job.where(queue: 'lel').delete
      JobBoard::Models.redis.del('queue:lel')
      JobBoard::Models.redis.srem('queues', 'lel')
      authorize(*auth)
    end

    after :each do
      JobBoard::Models::Job.where(queue: 'lel').delete
    end

    it 'returns 201' do
      post '/jobs/add', JSON.dump(job),
           'HTTP_CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(201)
    end

    it 'responds with nothing' do
      post '/jobs/add', JSON.dump(job),
           'HTTP_CONTENT_TYPE' => 'application/json'
      expect(last_response.body.length).to eq(0)
    end

    it 'adds the job to the database' do
      post '/jobs/add', JSON.dump(job),
           'HTTP_CONTENT_TYPE' => 'application/json'
      expect(JobBoard::Models::Job.where(queue: 'lel').count).to eq(1)
    end

    it 'adds the job to the assigned queue' do
      post '/jobs/add', JSON.dump(job),
           'HTTP_CONTENT_TYPE' => 'application/json'
      expect(JobBoard::Models.redis.llen('queue:lel')).to eq(1)
    end
  end

  describe 'GET /jobs/:job_id' do
    let(:job_id) { Time.now.to_i.to_s }
    let(:from) { 'worker+test@localhost' }

    before :each do
      JobBoard::Models::Job.where(queue: 'lel').delete
      JobBoard::Models.redis.multi do |conn|
        conn.del('queue:lel')
        conn.srem('queues', 'lel')
      end

      JobBoard::Services::CreateJob.run(
        params: {
          '@type' => 'job',
          'id' => job_id,
          'language' => 'pythorn',
          'os' => 'mcohess'
        }
      )

      JobBoard::Services::AllocateJobs.run(
        count: 1,
        from: from,
        jobs: [],
        queue: 'lel'
      )
      authorize(*auth)
    end

    after :each do
      JobBoard::Models::Job.where(queue: 'lel').delete
    end

    it 'responds 200' do
      get "/jobs/#{job_id}", nil, 'HTTP_FROM' => from
      expect(last_response.status).to eq(200)
    end

    it 'includes a job script' do
      get "/jobs/#{job_id}", nil, 'HTTP_FROM' => from
      response_body = JSON.parse(last_response.body)
      expect(response_body['job_script']).to_not be_nil
      job_script = response_body.fetch('job_script')
      expect(job_script['name']).to eq('main')
      expect(job_script['encoding']).to eq('base64')
      expect(job_script['content'].length).to be_positive
      expect(Base64.decode64(job_script['content'])).to match(/bash/)
    end

    it 'includes a job state URL' do
      get "/jobs/#{job_id}", nil, 'HTTP_FROM' => from
      response_body = JSON.parse(last_response.body)
      expect(response_body['job_state_url']).to_not be_nil
    end

    it 'includes a log parts URL' do
      get "/jobs/#{job_id}", nil, 'HTTP_FROM' => from
      response_body = JSON.parse(last_response.body)
      expect(response_body['log_parts_url']).to_not be_nil
    end

    it 'includes a JWT' do
      get "/jobs/#{job_id}", nil, 'HTTP_FROM' => from
      response_body = JSON.parse(last_response.body)
      expect(response_body['jwt']).to_not be_nil
    end
  end

  describe 'DELETE /jobs/:job_id' do
    let(:job_id) { Time.now.to_i.to_s }
    let(:from) { 'worker+test@localhost' }
    let(:jwt) { JobBoard::Services::CreateJWT.run(job_id: job_id) }

    before :each do
      JobBoard::Models::Job.where(job_id: job_id).delete
      JobBoard::Services::CreateJob.run(
        params: {
          'id' => job_id
        }
      )
    end

    after :each do
      JobBoard::Models::Job.where(job_id: job_id).delete
    end

    it 'deletes a job' do
      delete "/jobs/#{job_id}", nil,
             'HTTP_FROM' => from,
             'HTTP_AUTHORIZATION' => "Bearer #{jwt}"
      expect(last_response.status).to eq(204)
      expect(JobBoard::Models::Job.where(job_id: job_id).count).to be_zero
    end
  end
end
