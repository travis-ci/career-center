describe IMGRef::Models::Image do
  it 'has a primary key' do
    expect(described_class.primary_key).to_not be_empty
  end
end
