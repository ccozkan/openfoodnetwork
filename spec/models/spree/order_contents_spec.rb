# frozen_string_literal: true

require 'spec_helper'

describe Spree::OrderContents do
  let(:order) { Spree::Order.create }
  subject { described_class.new(order) }

  context "#add" do
    let(:variant) { create(:variant) }

    context 'given quantity is not explicitly provided' do
      it 'should add one line item' do
        line_item = subject.add(variant)
        expect(line_item.quantity).to eq 1
        expect(order.line_items.size).to eq 1
      end
    end

    it 'should add line item if one does not exist' do
      line_item = subject.add(variant, 1)
      expect(line_item.quantity).to eq 1
      expect(order.line_items.size).to eq 1
    end

    it 'should update line item if one exists' do
      subject.add(variant, 1)
      line_item = subject.add(variant, 1)
      expect(line_item.quantity).to eq 2
      expect(order.line_items.size).to eq 1
    end

    it "should update order totals" do
      expect(order.item_total.to_f).to eq 0.00
      expect(order.total.to_f).to eq 0.00

      subject.add(variant, 1)

      expect(order.item_total.to_f).to eq 19.99
      expect(order.total.to_f).to eq 19.99
    end
  end

  context "#remove" do
    let(:variant) { create(:variant) }

    context "given an invalid variant" do
      it "raises an exception" do
        expect {
          subject.remove(variant, 1)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'given quantity is not explicitly provided' do
      it 'should remove one line item' do
        line_item = subject.add(variant, 3)
        subject.remove(variant)

        expect(line_item.reload.quantity).to eq 2
      end
    end

    it 'should reduce line_item quantity if quantity is less the line_item quantity' do
      line_item = subject.add(variant, 3)
      subject.remove(variant, 1)

      expect(line_item.reload.quantity).to eq 2
    end

    it 'should remove line_item if quantity matches line_item quantity' do
      subject.add(variant, 1)
      subject.remove(variant, 1)

      expect(order.reload.find_line_item_by_variant(variant)).to be_nil
    end

    it "should update order totals" do
      expect(order.item_total.to_f).to eq 0.00
      expect(order.total.to_f).to eq 0.00

      subject.add(variant, 2)

      expect(order.item_total.to_f).to eq 39.98
      expect(order.total.to_f).to eq 39.98

      subject.remove(variant, 1)
      expect(order.item_total.to_f).to eq 19.99
      expect(order.total.to_f).to eq 19.99
    end
  end
end
