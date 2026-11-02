from rest_framework import serializers


class ReportFilterSerializer(serializers.Serializer):
    date_from = serializers.DateField(required=False)
    date_to = serializers.DateField(required=False)
    city = serializers.CharField(required=False, max_length=80)
    category = serializers.IntegerField(required=False)
    # Not "format": DRF reserves that query parameter for choosing a renderer.
    export = serializers.ChoiceField(choices=["json", "xlsx"], default="json")

    def validate(self, attrs):
        if attrs.get("date_from") and attrs.get("date_to") and attrs["date_from"] > attrs["date_to"]:
            raise serializers.ValidationError("date_from must be on or before date_to.")
        return attrs


class MerchantSalesQuerySerializer(serializers.Serializer):
    days = serializers.ChoiceField(choices=[7, 30, 90], default=30)
